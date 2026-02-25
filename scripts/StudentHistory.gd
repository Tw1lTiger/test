# ==============================================================================
# StudentHistory.gd — Хранение истории студента, прогресс, слабые зоны
# Автолоад. Данные сохраняются в user://student_history.json
# ==============================================================================
extends Node

const SAVE_PATH := "user://student_history.json"

## Массив словарей с историей ответов
var history: Array = []


func _ready() -> void:
	_load_history()
	print("[StudentHistory] Загружено %d записей" % history.size())


# ==============================================================================
# Сохранение / Загрузка
# ==============================================================================

func _load_history() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		history = []
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		history = []
		return
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Array:
		history = json.data
	else:
		history = []


func _save_history() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[StudentHistory] Не удалось открыть файл для записи!")
		return
	file.store_string(JSON.stringify(history, "\t"))
	file.close()


# ==============================================================================
# Добавление результата
# ==============================================================================

## Сохранить результат одного раунда
func save_result(data: Dictionary) -> void:
	# data = {
	#   "date": String,
	#   "topic": String,
	#   "question": String,
	#   "answer": String,
	#   "score": int (0-10),
	#   "max_score": int (10),
	#   "feedback": String,
	#   "weak_areas": Array[String]
	# }
	history.append(data)
	_save_history()
	print("[StudentHistory] Сохранён результат: %s — %d/%d" % [
		data.get("topic", "?"),
		data.get("score", 0),
		data.get("max_score", 10)
	])


# ==============================================================================
# Аналитика
# ==============================================================================

## Вернуть всю историю
func get_history() -> Array:
	return history


## Последние N записей
func get_recent(count: int = 20) -> Array:
	if history.size() <= count:
		return history.duplicate()
	return history.slice(history.size() - count)


## Прогресс по теме: массив {date, score}
func get_progress_by_topic(topic: String) -> Array:
	var results: Array = []
	var topic_lower := topic.to_lower()
	for entry in history:
		if str(entry.get("topic", "")).to_lower().contains(topic_lower):
			results.append({
				"date": entry.get("date", ""),
				"score": entry.get("score", 0),
				"max_score": entry.get("max_score", 10)
			})
	return results


## Средний балл по теме (0.0 - 10.0)
func get_average_score(topic: String = "") -> float:
	var total: float = 0.0
	var count: int = 0
	var topic_lower := topic.to_lower()
	for entry in history:
		if topic == "" or str(entry.get("topic", "")).to_lower().contains(topic_lower):
			total += float(entry.get("score", 0))
			count += 1
	if count == 0:
		return 0.0
	return total / count


## Слабые зоны — самые частые weak_areas
func get_weak_zones(limit: int = 5) -> Array:
	var zone_count: Dictionary = {}
	for entry in history:
		var areas = entry.get("weak_areas", [])
		if areas is Array:
			for area in areas:
				var a := str(area).to_lower()
				if a != "":
					zone_count[a] = zone_count.get(a, 0) + 1

	# Сортируем по количеству (убывание)
	var sorted_zones: Array = []
	for zone in zone_count:
		sorted_zones.append({"zone": zone, "count": zone_count[zone]})
	sorted_zones.sort_custom(func(a, b): return a["count"] > b["count"])

	var result: Array = []
	for i in range(mini(limit, sorted_zones.size())):
		result.append(sorted_zones[i])
	return result


## Слабые темы — темы с самым низким средним баллом (мин. 2 ответа)
func get_weak_topics(limit: int = 5) -> Array:
	var topic_scores: Dictionary = {} # topic -> {total, count}
	for entry in history:
		var t := str(entry.get("topic", "")).strip_edges()
		if t == "":
			continue
		if not topic_scores.has(t):
			topic_scores[t] = {"total": 0.0, "count": 0}
		topic_scores[t]["total"] += float(entry.get("score", 0))
		topic_scores[t]["count"] += 1

	var sorted_topics: Array = []
	for t in topic_scores:
		var data: Dictionary = topic_scores[t]
		if data["count"] >= 2:
			sorted_topics.append({
				"topic": t,
				"avg_score": data["total"] / data["count"],
				"count": data["count"]
			})
	sorted_topics.sort_custom(func(a, b): return a["avg_score"] < b["avg_score"])

	var result: Array = []
	for i in range(mini(limit, sorted_topics.size())):
		result.append(sorted_topics[i])
	return result


## Рекомендации на основе слабых зон
func get_recommendations() -> Array[String]:
	var recommendations: Array[String] = []
	var weak := get_weak_zones(3)
	var weak_topics := get_weak_topics(3)

	if weak.is_empty() and weak_topics.is_empty():
		recommendations.append("📚 Продолжайте отвечать на вопросы, чтобы система могла дать рекомендации.")
		return recommendations

	for zone in weak:
		recommendations.append("⚠️ Обратите внимание на: %s (встречается %d раз)" % [zone["zone"], zone["count"]])

	for t in weak_topics:
		recommendations.append("📖 Тема «%s» — ср. балл %.1f/10. Рекомендуется повторить." % [t["topic"], t["avg_score"]])

	if get_average_score() >= 8.0:
		recommendations.append("🌟 Отличная успеваемость! Средний балл: %.1f" % get_average_score())
	elif get_average_score() >= 5.0:
		recommendations.append("📈 Хороший прогресс! Средний балл: %.1f. Есть куда расти." % get_average_score())
	else:
		recommendations.append("💪 Средний балл: %.1f. Рекомендуется больше практики." % get_average_score())

	return recommendations


## Общая статистика для аналитики преподавателя
## Возвращает сводку для отправки на сервер
func get_summary() -> Dictionary:
	return {
		"total_answers": history.size(),
		"avg_score": get_average_score(),
		"weak_zones": get_weak_zones(3),
		"weak_topics": get_weak_topics(3),
	}


## Очистить всю историю
func clear_history() -> void:
	history.clear()
	_save_history()


# ==============================================================================
# Расширенная аналитика
# ==============================================================================

## Темы для повторения — агрегация всех topics_to_review
func get_topics_to_review(limit: int = 10) -> Array:
	var topic_count: Dictionary = {}
	for entry in history:
		var topics = entry.get("topics_to_review", [])
		if topics is Array:
			for t in topics:
				var ts := str(t).strip_edges()
				if ts != "":
					topic_count[ts] = topic_count.get(ts, 0) + 1

	var sorted_topics: Array = []
	for t in topic_count:
		sorted_topics.append({"topic": t, "count": topic_count[t]})
	sorted_topics.sort_custom(func(a, b): return a["count"] > b["count"])

	var result: Array = []
	for i in range(mini(limit, sorted_topics.size())):
		result.append(sorted_topics[i])
	return result


## Динамика результатов — средний балл по дням
func get_results_dynamics() -> Array:
	var daily: Dictionary = {}  # date_str -> {total, count}
	for entry in history:
		var date_str: String = str(entry.get("date", "")).left(10)  # YYYY-MM-DD
		if date_str == "":
			continue
		if not daily.has(date_str):
			daily[date_str] = {"total": 0.0, "count": 0}
		daily[date_str]["total"] += float(entry.get("score", 0))
		daily[date_str]["count"] += 1

	var sorted_dates: Array = []
	for d in daily:
		sorted_dates.append(d)
	sorted_dates.sort()

	var result: Array = []
	for d in sorted_dates:
		result.append({
			"date": d,
			"avg_score": daily[d]["total"] / daily[d]["count"],
			"count": daily[d]["count"]
		})
	return result


## Данные для плана изучения (передаются в GeminiAPI.generate_study_plan)
func get_study_plan_data() -> Dictionary:
	var weak_zones_raw := get_weak_zones(5)
	var weak_zones: Array = []
	for z in weak_zones_raw:
		weak_zones.append(str(z.get("zone", "")))

	var weak_topics_raw := get_weak_topics(5)
	var weak_topics: Array = []
	for t in weak_topics_raw:
		weak_topics.append(str(t.get("topic", "")))

	# Последние ошибки (score < 7)
	var recent_mistakes: Array = []
	var recent := get_recent(20)
	for entry in recent:
		if int(entry.get("score", 10)) < 7:
			recent_mistakes.append({
				"question": entry.get("question", ""),
				"answer": entry.get("answer", ""),
				"score": entry.get("score", 0)
			})

	return {
		"weak_zones": weak_zones,
		"weak_topics": weak_topics,
		"recent_mistakes": recent_mistakes
	}


## Экспорт результатов в текстовый файл
## custom_path: если указан — сохраняет туда, иначе в user://
func export_to_text(custom_path: String = "") -> String:
	var path := custom_path
	if path == "":
		var datetime := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		path = "user://report_%s.txt" % datetime

	var text := ""
	text += "=" .repeat(60) + "\n"
	text += "  ОТЧЁТ ОБ УСПЕВАЕМОСТИ СТУДЕНТА\n"
	text += "  Дата: %s\n" % Time.get_datetime_string_from_system()
	text += "=" .repeat(60) + "\n\n"

	# Общая статистика
	text += "📊 ОБЩАЯ СТАТИСТИКА:\n"
	text += "-" .repeat(40) + "\n"
	text += "  Всего ответов: %d\n" % history.size()
	text += "  Средний балл: %.1f / 10\n" % get_average_score()
	text += "\n"

	# Слабые зоны
	var weak := get_weak_zones(5)
	if not weak.is_empty():
		text += "⚠️ СЛАБЫЕ ЗОНЫ:\n"
		text += "-" .repeat(40) + "\n"
		for zone in weak:
			text += "  • %s (встречается %d раз)\n" % [zone["zone"], zone["count"]]
		text += "\n"

	# Слабые темы
	var weak_t := get_weak_topics(5)
	if not weak_t.is_empty():
		text += "📖 СЛАБЫЕ ТЕМЫ:\n"
		text += "-" .repeat(40) + "\n"
		for t in weak_t:
			text += "  • %s — ср. балл: %.1f/10 (%d ответов)\n" % [t["topic"], t["avg_score"], t["count"]]
		text += "\n"

	# Темы для повторения
	var review := get_topics_to_review(10)
	if not review.is_empty():
		text += "📚 ТЕМЫ ДЛЯ ПОВТОРЕНИЯ:\n"
		text += "-" .repeat(40) + "\n"
		for r in review:
			text += "  • %s (рекомендовано %d раз)\n" % [r["topic"], r["count"]]
		text += "\n"

	# Рекомендации
	var recs := get_recommendations()
	if not recs.is_empty():
		text += "💡 РЕКОМЕНДАЦИИ:\n"
		text += "-" .repeat(40) + "\n"
		for r in recs:
			text += "  %s\n" % r
		text += "\n"

	# Последние ответы
	var recent := get_recent(30)
	if not recent.is_empty():
		text += "📝 ПОСЛЕДНИЕ ОТВЕТЫ:\n"
		text += "-" .repeat(40) + "\n"
		for i in range(recent.size() - 1, -1, -1):
			var entry: Dictionary = recent[i]
			var date: String = str(entry.get("date", "")).left(16)
			var topic: String = str(entry.get("topic", "?"))
			var question: String = str(entry.get("question", "?"))
			var score: int = int(entry.get("score", 0))
			var answer: String = str(entry.get("answer", ""))
			var feedback: String = str(entry.get("feedback", ""))
			var explanation: String = str(entry.get("explanation", ""))
			var correct_answer: String = str(entry.get("correct_answer", ""))

			text += "\n  [%s] Тема: %s | Балл: %d/10\n" % [date, topic, score]
			text += "  Вопрос: %s\n" % question
			if answer != "":
				text += "  Ваш ответ: %s\n" % answer
			if correct_answer != "":
				text += "  Правильный ответ: %s\n" % correct_answer
			if explanation != "":
				text += "  Разбор: %s\n" % explanation
			if feedback != "":
				text += "  Отзыв: %s\n" % feedback

	text += "\n" + "=" .repeat(60) + "\n"
	text += "  Конец отчёта\n"
	text += "=" .repeat(60) + "\n"

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[StudentHistory] Не удалось создать файл отчёта!")
		return ""
	file.store_string(text)
	file.close()
	print("[StudentHistory] 📥 Отчёт сохранён: %s" % path)
	return path


## Экспорт плана изучения в текстовый файл
func export_study_plan_to_text(plan: Dictionary, custom_path: String = "") -> String:
	var path := custom_path
	if path == "":
		var datetime := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		path = "user://study_plan_%s.txt" % datetime

	var text := ""
	text += "=" .repeat(60) + "\n"
	text += "  ПЕРСОНАЛЬНЫЙ ПЛАН ИЗУЧЕНИЯ\n"
	text += "  Дата: %s\n" % Time.get_datetime_string_from_system()
	text += "=" .repeat(60) + "\n\n"

	var summary: String = plan.get("summary", "")
	if summary != "":
		text += "📋 РЕЗЮМЕ:\n%s\n\n" % summary
		text += "-" .repeat(40) + "\n\n"

	var plan_items: Array = plan.get("plan", [])
	if plan_items.is_empty():
		text += "Недостаточно данных для формирования плана.\n"
	else:
		var idx := 1
		for item in plan_items:
			if item is Dictionary:
				var topic_str: String = str(item.get("topic", "Тема %d" % idx))
				var desc_str: String = str(item.get("description", ""))
				var exercise_str: String = str(item.get("exercise", ""))

				text += "📖 %d. %s\n" % [idx, topic_str]
				if desc_str != "":
					text += "   📝 Что повторить: %s\n" % desc_str
				if exercise_str != "":
					text += "   🎯 Задание: %s\n" % exercise_str
				text += "\n"
				idx += 1

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[StudentHistory] Не удалось создать файл плана: " + path)
		return ""

	file.store_string(text)
	file.close()
	print("[StudentHistory] 📥 План сохранён: %s" % path)
	return path
