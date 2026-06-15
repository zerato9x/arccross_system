extends SceneTree

func _initialize():
	var img = Image.new()
	var err = img.load("res://Asset/UI.png")
	if err == OK:
		print("IMAGE SIZE: ", img.get_size())
	else:
		print("ERROR LOADING IMAGE")
	quit()
