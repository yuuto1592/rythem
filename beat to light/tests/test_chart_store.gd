extends TestCase

## Writes only under its own user:// folder and removes what it wrote.

var _dir := "user://test_chart_store_%d" % Time.get_ticks_usec()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and DirAccess.dir_exists_absolute(_dir):
		for file in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(file))
		DirAccess.remove_absolute(_dir)

func test_file_names_are_made_safe() -> void:
	check_eq(ChartStore.file_name_for("My Song #2"), "my_song_2", "spaces and symbols")
	check_eq(ChartStore.file_name_for("  04_hold-on  "), "04_hold-on", "keeps digits, _ and -")
	check_eq(ChartStore.file_name_for("曲"), "chart", "nothing usable left")

func test_save_writes_a_loadable_chart() -> void:
	var doc := ChartDoc.new()
	doc.title = "Saved"
	doc.add_note(4.0, 1)
	var path := _dir.path_join("saved_chart.json")
	check(ChartStore.write_chart(doc, path), "writes")
	var chart := Chart.load_from_file(path)
	check(chart != null, "loads back")
	if chart != null:
		check_eq(chart.title, "Saved", "title")
		check_eq(chart.notes.size(), 1, "notes")

func test_list_charts_in_a_folder() -> void:
	var doc := ChartDoc.new()
	ChartStore.write_chart(doc, _dir.path_join("b.json"))
	ChartStore.write_chart(doc, _dir.path_join("a.json"))
	check_eq(ChartStore.list_charts_in(_dir), PackedStringArray([_dir + "/a.json", _dir + "/b.json"]), "sorted")
	check(ChartStore.list_charts_in("user://no_such_folder").is_empty(), "missing folder is empty")

func test_music_is_found_next_to_the_chart() -> void:
	check_eq(ChartStore.resolve_music("user://songs/x.json", "song.ogg"), "user://songs/song.ogg", "bare name")
	check_eq(ChartStore.resolve_music("user://songs/x.json", "res://songs/a.ogg"), "res://songs/a.ogg", "res:// path")
	check_eq(ChartStore.resolve_music("user://songs/x.json", ""), "", "no music")
	check(ChartStore.load_music("user://songs/x.json", "missing.ogg") == null, "missing file loads as null")

func test_import_music_copies_and_loads() -> void:
	var name := ChartStore.import_music(ProjectSettings.globalize_path("res://tests/fixtures/beep.ogg"), _dir)
	check_eq(name, "beep.ogg", "returns the file name")
	check(FileAccess.file_exists(_dir.path_join("beep.ogg")), "copied next to the charts")
	var stream := ChartStore.load_music(_dir.path_join("chart.json"), name)
	check(stream is AudioStreamOggVorbis, "loads as Ogg Vorbis")
	if stream != null:
		check_near(stream.get_length(), 1.0, "one second long", 0.05)

func test_user_charts_are_told_apart() -> void:
	check(ChartStore.is_user_chart("user://songs/a.json"), "user://")
	check(not ChartStore.is_user_chart("res://songs/a.json"), "res://")

func test_import_music_never_overwrites_a_different_file() -> void:
	var beep := ProjectSettings.globalize_path("res://tests/fixtures/beep.ogg")
	DirAccess.make_dir_recursive_absolute(_dir)
	var other := FileAccess.open(_dir.path_join("beep.ogg"), FileAccess.WRITE)
	other.store_string("another song")
	other.close()
	check_eq(ChartStore.import_music(beep, _dir), "beep_2.ogg", "the copy gets a numbered name")
	check_eq(FileAccess.get_file_as_string(_dir.path_join("beep.ogg")), "another song", "the other file is untouched")
	check_eq(ChartStore.import_music(beep, _dir), "beep_2.ogg", "the same song again reuses the copy")
	check_eq(ChartStore.import_music(_dir.path_join("missing.ogg"), _dir), "", "a missing file is refused")

func test_music_travels_with_a_saved_chart() -> void:
	var beep := ProjectSettings.globalize_path("res://tests/fixtures/beep.ogg")
	var chart_path := _dir.path_join("song.json")
	check_eq(ChartStore.music_for(chart_path, "", beep), "beep.ogg", "music from elsewhere is copied next to the chart")
	check(FileAccess.file_exists(_dir.path_join("beep.ogg")), "and the copy is there")
	check_eq(ChartStore.music_for(_dir.path_join("other.json"), chart_path, "beep.ogg"), "beep.ogg",
			"music already next to the chart stays a bare file name")
	check_eq(ChartStore.music_for(chart_path, "", ""), "", "no music stays no music")
