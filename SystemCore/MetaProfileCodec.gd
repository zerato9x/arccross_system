extends RefCounted
class_name MetaProfileCodec

const VARIANT_TYPE_KEY := "__arccross_type"


static func encode_state(state: MetaProfileState, version: int) -> Dictionary:
	var payload: Dictionary = state.to_dict() if state != null else {}
	payload["version"] = version
	return encode_variant(payload)


static func decode_state(value: Variant) -> MetaProfileState:
	var decoded: Variant = decode_variant(value)
	return MetaProfileState.from_dict(decoded) if decoded is Dictionary else MetaProfileState.new()


static func encode_variant(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2I:
			return {VARIANT_TYPE_KEY: "Vector2i", "x": value.x, "y": value.y}
		TYPE_ARRAY:
			var encoded_array: Array = []
			for item in value:
				encoded_array.append(encode_variant(item))
			return encoded_array
		TYPE_DICTIONARY:
			var encoded_dictionary: Dictionary = {}
			for key in value.keys():
				encoded_dictionary[str(key)] = encode_variant(value[key])
			return encoded_dictionary
		_:
			return value


static func decode_variant(value: Variant) -> Variant:
	if value is Array:
		var decoded_array: Array = []
		for item in value:
			decoded_array.append(decode_variant(item))
		return decoded_array
	if value is Dictionary:
		if str(value.get(VARIANT_TYPE_KEY, "")) == "Vector2i":
			return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
		var decoded_dictionary: Dictionary = {}
		for key in value.keys():
			decoded_dictionary[key] = decode_variant(value[key])
		return decoded_dictionary
	return value
