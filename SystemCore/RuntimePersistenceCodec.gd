extends RefCounted
class_name RuntimePersistenceCodec

## JSON-safe codec for neutral runtime values. Resource reconstruction remains
## in RuntimeStateStore; this class only owns variant representation.

const VARIANT_TYPE_KEY := "__arccross_type"


static func encode_variant(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2I:
			return {
				VARIANT_TYPE_KEY: "Vector2i",
				"x": value.x,
				"y": value.y,
			}
		TYPE_VECTOR2:
			return {
				VARIANT_TYPE_KEY: "Vector2",
				"x": value.x,
				"y": value.y,
			}
		TYPE_COLOR:
			return {
				VARIANT_TYPE_KEY: "Color",
				"r": value.r,
				"g": value.g,
				"b": value.b,
				"a": value.a,
			}
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
		var encoded_type: String = value.get(VARIANT_TYPE_KEY, "")
		match encoded_type:
			"Vector2i":
				return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
			"Vector2":
				return Vector2(
					float(value.get("x", 0.0)),
					float(value.get("y", 0.0))
				)
			"Color":
				return Color(
					float(value.get("r", 0.0)),
					float(value.get("g", 0.0)),
					float(value.get("b", 0.0)),
					float(value.get("a", 1.0))
				)
		var decoded_dictionary: Dictionary = {}
		for key in value.keys():
			decoded_dictionary[key] = decode_variant(value[key])
		return decoded_dictionary
	return value
