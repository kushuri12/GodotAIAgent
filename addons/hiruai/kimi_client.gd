@tool
extends Node
## NVIDIA API client with STREAMING support.
## Delivers AI tokens in real-time via SSE (Server-Sent Events).
## No Python backend needed.

signal chat_completed(response_text: String)
signal chat_error(error_message: String)
signal token_received(token: String) # NEW: fires per-token for streaming UI
signal stream_started() # NEW: fires when first token arrives
signal stream_finished(full_text: String) # NEW: fires when stream is done

const API_URL := "https://integrate.api.nvidia.com/v1/chat/completions"
const CONFIG_PATH := "user://godot_ai_agent.cfg"

# Common NVIDIA Models
const MODELS = {
	"Kimi K2 Instruct": "moonshotai/kimi-k2-instruct",
	"Llama 3.1 405B": "meta/llama-3.1-405b-instruct",
	"Llama 3.1 70B": "meta/llama-3.1-70b-instruct",
	"Mistral Large 2": "mistralai/mistral-large-2-instruct",
	"Nemotron 340B": "nvidia/nemotron-4-340b-instruct",
	"Phi-3.5 MoE": "microsoft/phi-3.5-moe-instruct"
}

var api_key: String = ""
var current_model: String = "moonshotai/kimi-k2-instruct"
var _http: HTTPRequest
var _stream_http: HTTPClient # For SSE streaming
var _is_busy := false
var _is_streaming := false
var _cancel_requested := false
var _accumulated_text := ""
var _stream_buffer := ""

# Retry config
const MAX_RETRIES := 2
const RETRY_DELAY := 2.0
var _retry_count := 0
var _last_messages: Array = []


func _ready():
	_http = HTTPRequest.new()
	_http.timeout = 120
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	load_config()


func load_config():
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		api_key = cfg.get_value("api", "nvidia_key", "")
		current_model = cfg.get_value("api", "model", "moonshotai/kimi-k2-instruct")


func save_settings(key: String, model: String):
	api_key = key
	current_model = model
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("api", "nvidia_key", key)
	cfg.set_value("api", "model", model)
	cfg.save(CONFIG_PATH)


func is_busy() -> bool:
	return _is_busy


func cancel_request():
	if _is_busy:
		_cancel_requested = true
		if _is_streaming and _stream_http:
			_stream_http.close()
		_http.cancel_request()
		_is_busy = false
		_is_streaming = false


func send_chat(messages: Array):
	if _is_busy:
		chat_error.emit("Please wait for the current request to finish.")
		return
	if api_key.is_empty():
		chat_error.emit("API key not set. Click ⚙️ Settings to add your NVIDIA API key.")
		return

	_is_busy = true
	_cancel_requested = false
	_retry_count = 0
	_last_messages = messages.duplicate(true)
	_accumulated_text = ""

	# No extra warning suffix to avoid AI obsessive acknowledgment
	var msgs_copy = messages.duplicate(true)

	# Try streaming first, fallback to non-streaming
	_send_streaming(msgs_copy)


func _send_streaming(messages: Array):
	"""Use HTTPClient for SSE streaming."""
	_is_streaming = true
	_stream_buffer = ""
	_accumulated_text = ""

	# Run streaming in a coroutine so we don't block
	_do_stream_request(messages)


func _do_stream_request(messages: Array):
	"""Perform the actual streaming HTTP request."""
	_stream_http = HTTPClient.new()
	
	var err = _stream_http.connect_to_host("integrate.api.nvidia.com", 443, TLSOptions.client())
	if err != OK:
		_fallback_non_streaming(messages)
		return

	# Wait for connection
	var timeout_counter := 0
	while _stream_http.get_status() == HTTPClient.STATUS_CONNECTING or _stream_http.get_status() == HTTPClient.STATUS_RESOLVING:
		_stream_http.poll()
		await get_tree().create_timer(0.1).timeout
		timeout_counter += 1
		if timeout_counter > 150 or _cancel_requested: # 15 second timeout
			_stream_http.close()
			if _cancel_requested:
				_is_busy = false
				_is_streaming = false
				return
			_fallback_non_streaming(messages)
			return

	if _stream_http.get_status() != HTTPClient.STATUS_CONNECTED:
		_fallback_non_streaming(messages)
		return

	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json",
		"Accept: text/event-stream"
	])

	var body := JSON.stringify({
		"model": current_model,
		"messages": messages,
		"temperature": 0.4,
		"max_tokens": 4096,
		"stream": true
	})

	err = _stream_http.request(HTTPClient.METHOD_POST, "/v1/chat/completions", headers, body)
	if err != OK:
		_fallback_non_streaming(messages)
		return

	# Wait for response headers
	timeout_counter = 0
	while _stream_http.get_status() == HTTPClient.STATUS_REQUESTING:
		_stream_http.poll()
		await get_tree().create_timer(0.05).timeout
		timeout_counter += 1
		if timeout_counter > 600 or _cancel_requested: # 30 second timeout
			_stream_http.close()
			if _cancel_requested:
				_is_busy = false
				_is_streaming = false
				return
			_fallback_non_streaming(messages)
			return

	if not _stream_http.has_response():
		_fallback_non_streaming(messages)
		return

	var response_code = _stream_http.get_response_code()
	if response_code != 200:
		# Read error body
		var error_body := PackedByteArray()
		while _stream_http.get_status() == HTTPClient.STATUS_BODY:
			_stream_http.poll()
			var chunk = _stream_http.read_response_body_chunk()
			if chunk.size() > 0:
				error_body.append_array(chunk)
			else:
				await get_tree().create_timer(0.05).timeout

		var error_text = error_body.get_string_from_utf8()
		_stream_http.close()

		# Try retry
		if _retry_count < MAX_RETRIES:
			_retry_count += 1
			await get_tree().create_timer(RETRY_DELAY).timeout
			if not _cancel_requested:
				_do_stream_request(messages)
			return

		_is_busy = false
		_is_streaming = false
		_parse_error_response(response_code, error_text)
		return

	# Stream is live! Emit start signal
	stream_started.emit()
	var first_token := true

	# Read SSE stream
	while _stream_http.get_status() == HTTPClient.STATUS_BODY:
		if _cancel_requested:
			_stream_http.close()
			_is_busy = false
			_is_streaming = false
			return

		_stream_http.poll()
		var chunk = _stream_http.read_response_body_chunk()
		if chunk.size() > 0:
			_stream_buffer += chunk.get_string_from_utf8()
			_process_sse_buffer()
		else:
			await get_tree().create_timer(0.02).timeout

	# Done streaming
	_stream_http.close()
	_is_streaming = false
	_is_busy = false

	if _accumulated_text.strip_edges().is_empty():
		if _retry_count < MAX_RETRIES:
			_retry_count += 1
			_is_busy = true
			await get_tree().create_timer(RETRY_DELAY).timeout
			if not _cancel_requested:
				_do_stream_request(messages)
			return
		chat_error.emit("Empty response from AI after streaming.")
		return

	stream_finished.emit(_accumulated_text)
	chat_completed.emit(_accumulated_text)


func _process_sse_buffer():
	"""Parse SSE data lines from the buffer."""
	while "\n" in _stream_buffer:
		var newline_pos = _stream_buffer.find("\n")
		var line = _stream_buffer.substr(0, newline_pos).strip_edges()
		_stream_buffer = _stream_buffer.substr(newline_pos + 1)

		if line == "":
			continue
		if line == "data: [DONE]":
			continue
		if not line.begins_with("data: "):
			continue

		var json_str = line.substr(6) # Remove "data: " prefix
		var json = JSON.new()
		if json.parse(json_str) != OK:
			continue

		var data = json.data
		if not data is Dictionary:
			continue

		if data.has("choices") and data["choices"] is Array and data["choices"].size() > 0:
			var delta = data["choices"][0].get("delta", {})
			if delta is Dictionary and delta.has("content"):
				var content = delta["content"]
				if content is String and content != "":
					_accumulated_text += content
					token_received.emit(content)


func _fallback_non_streaming(messages: Array):
	"""Fallback to standard non-streaming request."""
	_is_streaming = false
	print("[HiruAI] Streaming unavailable, falling back to standard request...")

	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	])

	var body := JSON.stringify({
		"model": current_model,
		"messages": messages,
		"temperature": 0.4,
		"max_tokens": 4096,
		"stream": false
	})

	var request_err := _http.request(API_URL, headers, HTTPClient.METHOD_POST, body)
	if request_err != OK:
		_is_busy = false
		chat_error.emit("Failed to connect. Error code: %d" % request_err)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	_is_busy = false

	if result != HTTPRequest.RESULT_SUCCESS:
		# Retry logic for non-streaming
		if _retry_count < MAX_RETRIES:
			_retry_count += 1
			_is_busy = true
			await get_tree().create_timer(RETRY_DELAY).timeout
			if not _cancel_requested:
				_fallback_non_streaming(_last_messages)
			return

		var error_msg := "Connection failed."
		match result:
			HTTPRequest.RESULT_CANT_CONNECT:
				error_msg = "Cannot connect to NVIDIA API. Check your internet."
			HTTPRequest.RESULT_TIMEOUT:
				error_msg = "Request timed out (120s). Server took too long."
			HTTPRequest.RESULT_CANT_RESOLVE:
				error_msg = "Cannot resolve API hostname."
			_:
				error_msg = "Connection error (code: %d)" % result
		chat_error.emit(error_msg)
		return

	var response_text := body.get_string_from_utf8()

	if code != 200:
		_parse_error_response(code, response_text)
		return

	var json := JSON.new()
	if json.parse(response_text) != OK:
		chat_error.emit("Failed to parse API response.")
		return

	var data = json.data
	if data.has("choices") and data["choices"] is Array and data["choices"].size() > 0:
		var choice: Dictionary = data["choices"][0]
		var message: Dictionary = choice.get("message", {})
		var content: String = message.get("content", "")
		if content.is_empty():
			chat_error.emit("Empty response from AI.")
		else:
			chat_completed.emit(content)
	else:
		chat_error.emit("Unexpected response format from API.")


func _parse_error_response(code: int, response_text: String):
	"""Parse and emit a user-friendly error from API error responses."""
	var json := JSON.new()
	if json.parse(response_text) == OK and json.data is Dictionary:
		var data = json.data
		if data.has("error"):
			var err_data = data["error"]
			if err_data is Dictionary:
				chat_error.emit("API Error (%d): %s" % [code, err_data.get("message", "Unknown")])
			else:
				chat_error.emit("API Error (%d): %s" % [code, str(err_data)])
			return
	chat_error.emit("API returned status %d" % code)
