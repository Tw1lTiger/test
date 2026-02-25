# ==============================================================================
# GeminiAPI.gd — Обёртка для Groq API (OpenAI-совместимый)
# Генерация вопросов с ответами в одном запросе
# ==============================================================================
extends Node

## Сигнал: вопросы готовы (массив словарей {question, answers})
signal questions_ready(questions: Array)
## Сигнал: один вопрос готов
signal single_question_ready(question_data: Dictionary)
## Сигнал: ошибка
signal request_failed(error_message: String)
## Сигнал: вопрос для викторины готов
signal quiz_question_ready(data: Dictionary)
## Сигнал: ответы оценены
signal answers_evaluated(results: Dictionary)
signal study_plan_ready(plan: Dictionary)

## Groq API — используем 70b модель (она лучше следует инструкциям JSON)
const API_URL := "https://api.groq.com/openai/v1/chat/completions"
const API_KEY := ""
const MODEL := "llama-3.3-70b-versatile"

## Google Gemini (Backup)
const GOOGLE_KEY := ""
const GOOGLE_MODEL := "gemini-2.5-flash"  # Используем стабильную версию для надежности
const GOOGLE_URL_BASE := "https://generativelanguage.googleapis.com/v1beta/models/"

const REQUEST_TIMEOUT := 20.0

## Задержка между запросами (секунды) — чтобы не упираться в rate limit
const REQUEST_COOLDOWN := 3.0

var _http_request: HTTPRequest
var _api_key: String = API_KEY

var _retry_count: int = 0
const MAX_RETRIES := 1 # Быстрое переключение
const RETRY_DELAY := 1.5

## Текущий провайдер (0=Groq, 1=Google)
var _current_provider: int = 0
const PROVIDER_GROQ := 0
const PROVIDER_GOOGLE := 1

## Текущий режим запроса: false = пакет (batch), true = один вопрос
var _is_single_mode: bool = false

## Список уже заданных вопросов, чтобы не повторять
var _asked_questions: Array[String] = []

## Список уже использованных тем
var _used_themes: Array[String] = []

## Регулярное выражение для проверки кириллицы
var _cyrillic_regex: RegEx


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	_http_request.timeout = REQUEST_TIMEOUT
	randomize() # Инициализация ГСЧ.
	_http_request.use_threads = true
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

	_cyrillic_regex = RegEx.new()
	_cyrillic_regex.compile("^[а-яёА-ЯЁ\\-]+$")

	print("[GroqAPI] Готов к работе (модель: %s)" % MODEL)


func _get_headers() -> Array:
	return [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _api_key,
	]


func set_api_key(key: String) -> void:
	_api_key = key
	print("[GroqAPI] Ключ API установлен вручную")


# ==============================================================================
# Генерация вопросов
# ==============================================================================

var _switch_count: int = 0
const MAX_SWITCHES := 12

func generate_questions_batch() -> void:
	_retry_count = 0
	_switch_count = 0
	_is_single_mode = false
	_do_request()


func generate_single_question() -> void:
	_retry_count = 0
	_switch_count = 0
	_is_single_mode = true
	_do_single_request()


# ... (clear_history, _pick_fresh_theme, _do_single_request, _do_request same as before) 
# I will actually skip efficient replacement of the whole file if I can targeted replace.
# The user wants "after each question try again".
# "ИИ снова быстро отлетает" -> The retry logic is failing.

func _handle_transport_error(error: int) -> void:
	print("[API] Transport Error: %d" % error)
	_switch_provider_and_retry("Transport Error %d" % error)


func _switch_provider_and_retry(reason: String) -> void:
	_switch_count += 1
	if _switch_count > MAX_SWITCHES:
		print("[API] ❌ Превышен лимит переключений провайдеров (%d). Сдаюсь." % MAX_SWITCHES)
		if _current_provider == PROVIDER_GOOGLE:
			request_failed.emit("Google API failed: " + reason)
		else:
			request_failed.emit("Groq API failed: " + reason)
		return

	var next_provider_name := "Google" if _current_provider == PROVIDER_GROQ else "Groq"
	print("[API] 🔄 (%d/%d) Переключение на %s из-за: %s" % [_switch_count, MAX_SWITCHES, next_provider_name, reason])
	
	if _current_provider == PROVIDER_GROQ:
		_current_provider = PROVIDER_GOOGLE
	else:
		_current_provider = PROVIDER_GROQ
		
	_retry_count = 0  # Сброс попыток rate limit для нового провайдера
	
	# Небольшая задержка перед запросом к новому провайдеру
	await get_tree().create_timer(1.0).timeout
	
	if _is_single_mode:
		_do_single_request()
	else:
		_do_request()


func clear_history() -> void:
	_asked_questions.clear()
	_used_themes.clear()


## Выбрать тему, которая ещё не использовалась
func _pick_fresh_theme(themes: Array) -> String:
	var available: Array[String] = []
	for t in themes:
		if not _used_themes.has(t):
			available.append(t)
	# Если все темы уже были — сбросить и начать заново
	if available.is_empty():
		_used_themes.clear()
		for t in themes:
			available.append(t)
	available.shuffle()
	var picked: String = available[0]
	_used_themes.append(picked)
	return picked


func _do_single_request() -> void:
	var all_themes := [
		"хищники Африки", "тропические фрукты", "морские существа",
		"древние цивилизации", "ядовитые растения", "музыкальные жанры",
		"олимпийские виды спорта", "драгоценные камни", "столицы Европы",
		"космические объекты", "средневековое оружие", "научные открытия",
		"мифологические существа", "экзотические блюда", "вымершие животные",
		"музыкальные инструменты", "архитектурные стили",
		"зимние виды спорта", "морские профессии", "японская культура",
		"минералы и породы", "танцевальные стили", "явления природы",
		"кулинарные специи", "изобретения XX века", "ночные животные",
		"домашние животные", "овощи и корнеплоды", "ягоды",
		"речные рыбы", "птицы России", "деревья", "цветы и растения",
		"насекомые", "грибы", "породы собак", "породы кошек",
		"виды чая", "виды кофе", "молочные продукты", "крупы и каши",
		"виды хлеба", "супы мира", "специи Азии", "десерты мира",
		"марки автомобилей", "персонажи Гарри Поттера", "стихии", 
		"созвездия", "химические элементы", "языки программирования",
		"части тела", "предметы мебели", "одежда", "обувь", "головные уборы",
		"инструменты", "канцтовары", "посуда", "бытовая техника",
		"жанры кино", "советские фильмы", "супергерои Marvel", "персонажи DC",
		"покемоны", "блоки Minecraft", "мобы Minecraft", "герои Dota 2",
		"чемпионы League of Legends", "оружие CS:GO", "карты CS:GO",
		"города России", "реки России", "озера мира", "моря и океаны",
		"горные вершины", "острова", "страны Азии", "страны Африки",
		"штаты США", "европейские языки", "валюты мира",
		"писатели-классики", "поэты Серебряного века", "русские сказки",
		"греческие боги", "римские императоры", "викинги", "рыцари",
		"пираты", "индейцы", "динозавры", "птицы джунглей",
		"обитатели пустыни", "животные Арктики", "глубоководные рыбы",
		"марки телефонов", "социальные сети", "мессенджеры",
		"праздники", "виды спорта с мячом", "боевые искусства",
		"настольные игры", "карточные масти", "шахматные фигуры",
		"цвета радуги", "драгоценные металлы", "сплавы", "газы",
		"части цветка", "органы человека", "кости скелета",
		"планеты Солнечной системы", "спутники планет", "типы звезд",
		"виды облаков", "стихийные бедствия", "времена года",
		"месяцы", "дни недели", "знаки зодиака",
		"цифры", "математические фигуры", "единицы измерения",
		"жанры живописи", "великие художники", "композиторы",
		"рок-группы", "рэп-исполнители", "поп-звезды",
		"виды транспорта", "марки самолетов", "типы кораблей",
		"строительные инструменты", "садовые инструменты", "запчасти машины",
		"виды ткани", "виды бумаги", "типы узлов", "виды обуви"
	]

	var theme: String
	if GameManager.custom_topic.strip_edges() != "":
		theme = GameManager.custom_topic.strip_edges()
	else:
		theme = _pick_fresh_theme(all_themes)

	# Собираем ВСЕ заданные вопросы для исключения
	var exclude_str := ""
	if not _asked_questions.is_empty():
		exclude_str = "\n\nНИКОГДА НЕ ПОВТОРЯЙ эти вопросы: " + ", ".join(_asked_questions)

	var prompt := """Ты — креативный автор вопросов для викторины.
Твоя задача — придумать ИНТЕРЕСНУЮ и НЕОБЫЧНУЮ категорию для перечисления, вдохновленную темой: "%s".
Избегай скучных и банальных формулировок. Постарайся удивить игроков.
%s

СТРОГИЕ ПРАВИЛА:
1. ФОРМУЛИРОВКА ВОПРОСА:
   - Вопрос ДОЛЖЕН начинаться с фразы "Назовите..." или "Перечислите...".
   - Он должен просить назвать объект или сущность из конкретной категории.
   - ПРИМЕРЫ ХОРОШИХ ВОПРОСОВ:
	 - "Назовите любой знак зодиака"
	 - "Назовите любой вид спорта с мячом"
	 - "Назовите любого покемона первого поколения"
	 - "Назовите персонажей мультсериала Скуби-Ду"
	 - "Назовите марку японского автомобиля"
   - ПРИМЕРЫ ПЛОХИХ ВОПРОСОВ (ЗАПРЕЩЕНО):
	 - "Какого цвета трава?" (Факт)
	 - "Кто написал Муму?" (Один ответ)
	 - "Имеет ли чай зеленый цвет?" (Да/Нет)

2. ОТВЕТЫ:
   - Вопрос должен подразумевать МНОЖЕСТВО правильных ответов (открытый список).
   - Предоставь ровно 40 вариантов ответов.
   - Все ответы — существительные, Им. падеж, Ед. число (где возможно).
   - Имена собственные писать с Заглавной буквы.

3. КАЧЕСТВО:
   - Только реальные объекты.

Ответь ТОЛЬКО JSON-ом формата:
[{"question":"Назовите...","answers":["ответ1","ответ2",...]}]""" % [theme, exclude_str]

	if _current_provider == PROVIDER_GROQ:
		var body := {
			"model": MODEL,
			"messages": [
				{"role": "system", "content": "Ты отвечаешь ТОЛЬКО валидным JSON. Никакого текста."},
				{"role": "user", "content": prompt},
			],
			"temperature": 0.8,
			"max_tokens": 1500,
		}

		print("[GroqAPI] Генерирую вопрос (тема: %s)..." % theme)
		var error := _http_request.request(API_URL, _get_headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
		if error != OK:
			_handle_transport_error(error)

	elif _current_provider == PROVIDER_GOOGLE:
		var google_url := "%s%s:generateContent?key=%s" % [GOOGLE_URL_BASE, GOOGLE_MODEL, GOOGLE_KEY]
		# Google API требует другой формат prompt
		var google_prompt := prompt + "\n\nОтветь ТОЛЬКО JSON."
		var body := {
			"contents": [{
				"parts": [{"text": google_prompt}]
			}],
			"generationConfig": {
				"temperature": 0.8,
				"maxOutputTokens": 1500,
				"responseMimeType": "application/json"
			}
		}

		print("[GoogleAPI] Генерирую вопрос (тема: %s)..." % theme)
		var error := _http_request.request(google_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
		if error != OK:
			_handle_transport_error(error)


func _do_request() -> void:
	var all_themes := [
		"хищники Африки", "тропические фрукты", "морские существа",
		"древние цивилизации", "ядовитые растения", "музыкальные жанры",
		"олимпийские виды спорта", "драгоценные камни", "столицы Европы",
		"космические объекты", "средневековое оружие", "научные открытия",
		"мифологические существа", "экзотические блюда", "вымершие животные",
		"музыкальные инструменты", "архитектурные стили",
		"зимние виды спорта", "морские профессии", "японская культура",
		"минералы и породы", "танцевальные стили", "явления природы",
		"кулинарные специи", "изобретения XX века", "ночные животные",
		"домашние животные", "овощи и корнеплоды", "ягоды",
		"речные рыбы", "птицы России", "деревья", "цветы и растения",
		"насекомые", "грибы", "породы собак", "породы кошек",
		"виды чая", "виды кофе", "молочные продукты", "крупы и каши",
		"виды хлеба", "супы мира", "специи Азии", "десерты мира",
		"марки автомобилей", "персонажи Гарри Поттера", "стихии", 
		"созвездия", "химические элементы", "языки программирования",
		"части тела", "предметы мебели", "одежда", "обувь", "головные уборы",
		"инструменты", "канцтовары", "посуда", "бытовая техника",
		"жанры кино", "советские фильмы", "супергерои Marvel", "персонажи DC",
		"покемоны", "блоки Minecraft", "мобы Minecraft", "герои Dota 2",
		"чемпионы League of Legends", "оружие CS:GO", "карты CS:GO",
		"города России", "реки России", "озера мира", "моря и океаны",
		"горные вершины", "острова", "страны Азии", "страны Африки",
		"штаты США", "европейские языки", "валюты мира",
		"писатели-классики", "поэты Серебряного века", "русские сказки",
		"греческие боги", "римские императоры", "викинги", "рыцари",
		"пираты", "индейцы", "динозавры", "птицы джунглей",
		"обитатели пустыни", "животные Арктики", "глубоководные рыбы",
		"марки телефонов", "социальные сети", "мессенджеры",
		"праздники", "виды спорта с мячом", "боевые искусства",
		"настольные игры", "карточные масти", "шахматные фигуры",
		"цвета радуги", "драгоценные металлы", "сплавы", "газы",
		"части цветка", "органы человека", "кости скелета",
		"планеты Солнечной системы", "спутники планет", "типы звезд",
		"виды облаков", "стихийные бедствия", "времена года",
		"месяцы", "дни недели", "знаки зодиака",
		"цифры", "математические фигуры", "единицы измерения",
		"жанры живописи", "великие художники", "композиторы",
		"рок-группы", "рэп-исполнители", "поп-звезды",
		"виды транспорта", "марки самолетов", "типы кораблей",
		"строительные инструменты", "садовые инструменты", "запчасти машины",
		"виды ткани", "виды бумаги", "типы узлов", "виды обуви"
	]
	
	var themes: Array[String] = []
	if GameManager.custom_topic.strip_edges() != "":
		themes.append(GameManager.custom_topic.strip_edges())
	else:
		all_themes.shuffle()
		for i in range(mini(5, all_themes.size())):
			themes.append(all_themes[i])
			
	var themes_str := ", ".join(themes)

	var prompt := """Ты — креативный автор вопросов для викторины.
Сгенерируй 5 НЕОБЫЧНЫХ и ИНТЕРЕСНЫХ категорий для перечисления на РАЗНЫЕ темы (Темы: %s).
Постарайся удивить игроков нетривиальными вопросами.

СТРОГИЕ ПРАВИЛА:
1. ФОРМУЛИРОВКА ВОПРОСА:
   - Вопрос ДОЛЖЕН просить называть объекты из категории.
   - Формат: "Назовите...", "Перечислите...".
   - ХОРОШО: "Назовите фрукт", "Назовите планету", "Назовите химический элемент".
   - ПЛОХО: "Что такое...", "Где находится...", "Кто такой...".

2. ОТВЕТЫ:
   - К каждому вопросу дай 40 вариантов ответов.
   - Все ответы — существительные, Им. падеж, Ед. число.
   - Реальные слова.

Ответь ТОЛЬКО JSON-ом:
[{"question":"Назовите...","answers":["ответ1",...]}]""" % themes_str

	if _current_provider == PROVIDER_GROQ:
		var body := {
			"model": MODEL,
			"messages": [
				{"role": "system", "content": "Ты отвечаешь ТОЛЬКО валидным JSON. Никакого текста."},
				{"role": "user", "content": prompt},
			],
			"temperature": 0.8,
			"max_tokens": 6000,
		}

		print("[GroqAPI] Генерирую вопросы (темы: %s)..." % themes_str)
		var error := _http_request.request(API_URL, _get_headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
		if error != OK:
			_handle_transport_error(error)

	elif _current_provider == PROVIDER_GOOGLE:
		var google_url := "%s%s:generateContent?key=%s" % [GOOGLE_URL_BASE, GOOGLE_MODEL, GOOGLE_KEY]
		var google_prompt := prompt + "\n\nОтветь ТОЛЬКО JSON."
		var body := {
			"contents": [{
				"parts": [{"text": google_prompt}]
			}],
			"generationConfig": {
				"temperature": 0.8,
				"maxOutputTokens": 6000,
				"responseMimeType": "application/json"
			}
		}

		print("[GoogleAPI] Генерирую вопросы (темы: %s)..." % themes_str)
		var error := _http_request.request(google_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
		if error != OK:
			_handle_transport_error(error)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 429:
		_retry_count += 1
		# Для Groq пробуем повторить пару раз перед переключением
		if _current_provider == PROVIDER_GROQ and _retry_count <= MAX_RETRIES:
			var delay := RETRY_DELAY * _retry_count
			print("[GroqAPI] 429 Rate Limit, повтор %d/%d через %.0fс..." % [_retry_count, MAX_RETRIES, delay])
			await get_tree().create_timer(delay).timeout
			if _is_single_mode: _do_single_request()
			else: _do_request()
			return
		else:
			# Google 429 или исчерпаны попытки Groq — переключаемся
			_switch_provider_and_retry("Rate Limit 429")
			return

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var error_body := body.get_string_from_utf8()
		print("[API] Ошибка %d (код %d). Body: %s" % [result, response_code, error_body.left(500)])
		_switch_provider_and_retry("HTTP Error %d" % response_code)
		return

	var response_text := ""
	if _current_provider == PROVIDER_GROQ:
		response_text = _parse_groq_response(body)
	else:
		response_text = _parse_google_response(body)

	if response_text == "":
		print("[API] ⚠️ Пустой/ошибочный ответ парсера.")
		_switch_provider_and_retry("Parse Error / Empty Response")
		return

	print("[GroqAPI] 📝 Ответ (первые 300 символов): %s" % response_text.left(300))

	var questions := _parse_questions_json(response_text)
	if questions.is_empty():
		print("[GroqAPI] Не удалось распарсить ответ или он пустой: %s" % response_text.left(1000))
		_switch_provider_and_retry("Groq Parse Error")
		return

	print("[GroqAPI] ✅ Получено %d вопросов!" % questions.size())

	if _is_single_mode and not questions.is_empty():
		var q: Dictionary = questions[0]
		_asked_questions.append(q["question"])
		single_question_ready.emit(q)
	else:
		# В batch режиме тоже запоминаем вопросы
		for q in questions:
			_asked_questions.append(q["question"])
		questions_ready.emit(questions)


## Проверяем, что слово — одно кириллическое слово
func _is_valid_answer(word: String) -> bool:
	if word.length() < 2 or word.length() > 25:
		return false
	# Отклоняем словосочетания (содержат пробел)
	if word.contains(" "):
		return false
	# Должно содержать только кириллицу и дефис
	if not _cyrillic_regex.search(word):
		return false
	return true


func _parse_questions_json(text: String) -> Array:
	var json_text := text.strip_edges()
	if json_text.begins_with("```"):
		json_text = json_text.replace("```json", "").replace("```", "").strip_edges()

	var start_idx := json_text.find("[")
	var end_idx := json_text.rfind("]")
	if start_idx == -1 or end_idx == -1 or end_idx <= start_idx:
		print("[GroqAPI] JSON не найден: %s" % json_text.left(200))
		return []
	json_text = json_text.substr(start_idx, end_idx - start_idx + 1)

	var json := JSON.new()
	if json.parse(json_text) != OK:
		print("[GroqAPI] Parse error: %s" % json.get_error_message())
		return []

	var data: Array = json.data
	var parse_result: Array = []
	for item in data:
		if item is Dictionary and item.has("question") and item.has("answers"):
			var answers: Array[String] = []
			for a in item["answers"]:
				if a is String:
					var cleaned: String = a.strip_edges().to_lower()
					if _is_valid_answer(cleaned) and not answers.has(cleaned):
						answers.append(cleaned)
			if item["question"] != "" and answers.size() >= 3:
				# Проверяем, что вопрос не повторяется
				if not _asked_questions.has(item["question"]):
					parse_result.append({"question": item["question"], "answers": answers})
	return parse_result


## Парсинг ответа Groq (OpenAI-совместимый формат)
func _parse_groq_response(body: PackedByteArray) -> String:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		print("[GroqAPI] JSON parse ошибка в ответе")
		return ""
	var data: Dictionary = json.data
	var choices: Array = data.get("choices", [])
	if choices.is_empty():
		print("[GroqAPI] Нет choices в ответе")
		return ""
	var message: Dictionary = choices[0].get("message", {})
	var content: String = message.get("content", "")
	return content.strip_edges()





## Парсинг ответа Google Gemini
func _parse_google_response(body: PackedByteArray) -> String:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		print("[GoogleAPI] JSON parse error")
		return ""
	var data: Dictionary = json.data
	# Google format: { "candidates": [ { "content": { "parts": [ { "text": "..." } ] } } ] }
	var candidates: Array = data.get("candidates", [])
	if candidates.is_empty():
		print("[GoogleAPI] No candidates")
		return ""
	var content: Dictionary = candidates[0].get("content", {})
	var parts: Array = content.get("parts", [])
	if parts.is_empty():
		print("[GoogleAPI] No parts")
		return ""
	return parts[0].get("text", "").strip_edges()


# ==============================================================================
# Валидация слова через ИИ (Fallback)
# ==============================================================================

## Проверяет слово через API, если его нет в локальном списке
## Возвращает true/false. Асинхронная функция!
func validate_word(category: String, word: String) -> bool:
	print("[GeminiAPI] 🔍 Проверяю слово \"%s\" для категории \"%s\"..." % [word, category])
	
	var prompt := """Категория: %s
Слово: %s
Является ли это слово (или его форма) правильным ответом для этой категории?
Ответь СТРОГО "YES" или "NO".""" % [category, word]

	# Создаем временный HTTPRequest
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 10.0 # Быстрый тайм-аут
	
	# Формируем тело запроса (используем Groq для скорости, или Google если Groq занят/ошибка)
	# Для простоты используем текущий провайдер, но с приоритетом скорости
	
	var url := API_URL
	var headers := _get_headers()
	var body_json := ""
	
	# Используем Groq (Llama) так как он быстрее
	var body_dict := {
		"model": MODEL,
		"messages": [
			{"role": "system", "content": "You are a strict validator. Reply only YES or NO."},
			{"role": "user", "content": prompt},
		],
		"temperature": 0.0, # Максимальная точность
		"max_tokens": 5,
	}
	body_json = JSON.stringify(body_dict)
	
	var error := req.request(url, headers, HTTPClient.METHOD_POST, body_json)
	if error != OK:
		print("[GeminiAPI] Ошибка отправки запроса валидации")
		req.queue_free()
		return false
	
	# Ждем ответа
	var response = await req.request_completed
	# response = [result, response_code, headers, body]
	var result_code: int = response[0]
	var response_code: int = response[1]
	var response_body: PackedByteArray = response[3]
	
	req.queue_free() # Удаляем узел
	
	if result_code != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[GeminiAPI] Ошибка валидации: код %d" % response_code)
		return false
		
	var resp_str := _parse_groq_response(response_body).strip_edges().to_upper()
	print("[GeminiAPI] Ответ валидатора: %s" % resp_str)
	
	if resp_str.contains("YES") or resp_str.contains("ДА"):
		return true
		
	return false


# ==============================================================================
# Викторина — Генерация открытых вопросов
# ==============================================================================

## Генерирует один открытый вопрос по теме для викторины
func generate_quiz_question(topic: String) -> void:
	print("[GeminiAPI] 📝 Генерирую вопрос для викторины (тема: %s)..." % topic)
	
	var exclude_str := ""
	if not _asked_questions.is_empty():
		exclude_str = "\n\nНИКОГДА НЕ ПОВТОРЯЙ эти вопросы: " + ", ".join(_asked_questions)

	var prompt := """Ты — преподаватель, создающий вопросы для проверки знаний студентов.
Тема: "%s".
%s

ПРАВИЛА:
1. Придумай ОДИН интересный вопрос по этой теме, который требует РАЗВЁРНУТОГО ответа (2-5 предложений).
2. Вопрос должен проверять понимание материала, а не просто запоминание фактов.
3. Вопрос не должен быть слишком простым (да/нет) или слишком сложным.
4. Определи ключевые пункты, которые должен содержать хороший ответ.

ПРИМЕРЫ ХОРОШИХ ВОПРОСОВ:
- "Объясните, как работает фотосинтез и почему он важен для жизни на Земле."
- "Расскажите о причинах и последствиях Великой французской революции."
- "Опишите принцип работы двигателя внутреннего сгорания."

Ответь ТОЛЬКО JSON:
{"question": "...", "key_points": ["пункт1", "пункт2", "пункт3"]}""" % [topic, exclude_str]

	var req := HTTPRequest.new()
	req.name = "QuizQuestionRequest"
	add_child(req)
	req.timeout = REQUEST_TIMEOUT

	var url := ""
	var headers: Array = []
	var body_json := ""

	if _current_provider == PROVIDER_GROQ:
		url = API_URL
		headers = _get_headers()
		var body_dict := {
			"model": MODEL,
			"messages": [
				{"role": "system", "content": "Ты отвечаешь ТОЛЬКО валидным JSON. Никакого другого текста."},
				{"role": "user", "content": prompt},
			],
			"temperature": 0.7,
			"max_tokens": 500,
		}
		body_json = JSON.stringify(body_dict)
	else:
		url = "%s%s:generateContent?key=%s" % [GOOGLE_URL_BASE, GOOGLE_MODEL, GOOGLE_KEY]
		headers = ["Content-Type: application/json"]
		var body_dict := {
			"contents": [{"parts": [{"text": prompt + "\n\nОтветь ТОЛЬКО JSON."}]}],
			"generationConfig": {
				"temperature": 0.7,
				"maxOutputTokens": 500,
				"responseMimeType": "application/json"
			}
		}
		body_json = JSON.stringify(body_dict)

	var error := req.request(url, headers, HTTPClient.METHOD_POST, body_json)
	if error != OK:
		req.queue_free()
		request_failed.emit("Ошибка запроса вопроса викторины")
		return

	var response = await req.request_completed
	var result_code: int = response[0]
	var response_code: int = response[1]
	var response_body: PackedByteArray = response[3]
	req.queue_free()

	if result_code != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[GeminiAPI] Ошибка генерации вопроса: код %d" % response_code)
		# Попробуем другой провайдер
		if _current_provider == PROVIDER_GROQ:
			_current_provider = PROVIDER_GOOGLE
		else:
			_current_provider = PROVIDER_GROQ
		# Повторный запрос
		generate_quiz_question(topic)
		return

	var resp_text := ""
	if _current_provider == PROVIDER_GROQ or (_current_provider == PROVIDER_GOOGLE and response_code == 200):
		# Определяем какой провайдер отослал ответ (по текущему state)
		pass
	
	# Парсим ответ
	resp_text = _parse_response_universal(response_body)
	
	if resp_text == "":
		request_failed.emit("Пустой ответ для вопроса викторины")
		return

	# Парсим JSON
	var json_text := resp_text.strip_edges()
	if json_text.begins_with("```"):
		json_text = json_text.replace("```json", "").replace("```", "").strip_edges()
	
	# Ищем JSON объект
	var start_idx := json_text.find("{")
	var end_idx := json_text.rfind("}")
	if start_idx == -1 or end_idx == -1:
		# Может быть массив
		start_idx = json_text.find("[")
		end_idx = json_text.rfind("]")
	if start_idx == -1 or end_idx == -1:
		request_failed.emit("Не удалось распарсить вопрос викторины")
		return
	json_text = json_text.substr(start_idx, end_idx - start_idx + 1)

	var json := JSON.new()
	if json.parse(json_text) != OK:
		request_failed.emit("JSON parse error: " + json.get_error_message())
		return

	var data = json.data
	# Может вернуть массив или объект
	if data is Array and data.size() > 0:
		data = data[0]
	
	if data is Dictionary and data.has("question"):
		_asked_questions.append(data["question"])
		var result := {
			"question": data["question"],
			"key_points": data.get("key_points", [])
		}
		print("[GeminiAPI] ✅ Вопрос викторины: \"%s\"" % result["question"])
		quiz_question_ready.emit(result)
	else:
		request_failed.emit("Неверный формат вопроса викторины")


## Универсальный парсер ответа (Groq или Google)
func _parse_response_universal(body: PackedByteArray) -> String:
	var raw := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(raw) != OK:
		return ""
	var data: Dictionary = json.data
	
	# Groq format
	var choices: Array = data.get("choices", [])
	if not choices.is_empty():
		var message: Dictionary = choices[0].get("message", {})
		return message.get("content", "").strip_edges()
	
	# Google format
	var candidates: Array = data.get("candidates", [])
	if not candidates.is_empty():
		var content: Dictionary = candidates[0].get("content", {})
		var parts: Array = content.get("parts", [])
		if not parts.is_empty():
			return parts[0].get("text", "").strip_edges()
	
	return ""


# ==============================================================================
# Викторина — Оценка ответов студентов
# ==============================================================================

## Оценивает развёрнутые ответы студентов по вопросу
func evaluate_answers(question: String, key_points: Array, answers_dict: Dictionary, is_retry: bool = false) -> void:
	print("[GeminiAPI] 🔍 Оцениваю %d ответов..." % answers_dict.size())

	if answers_dict.is_empty():
		answers_evaluated.emit({})
		return

	# Формируем текст ответов
	var answers_text := ""
	for peer_id in answers_dict:
		var answer_str: String = str(answers_dict[peer_id])
		answers_text += "Студент_%s: \"%s\"\n" % [str(peer_id), answer_str]

	var key_points_str := ", ".join(key_points) if not key_points.is_empty() else "нет конкретных пунктов"

	var prompt := """Ты — строгий, но справедливый преподаватель.
Оцени ответы студентов на вопрос.

ВОПРОС: %s
КЛЮЧЕВЫЕ ПУНКТЫ, которые должны быть в ответе: %s

ОТВЕТЫ СТУДЕНТОВ:
%s

ПРАВИЛА ОЦЕНКИ:
1. Оценка от 0 до 10 баллов.
2. 0 — пустой или абсолютно неправильный ответ.
3. 3-4 — частично правильный, но неполный ответ.
4. 5-6 — правильный, но поверхностный ответ.
5. 7-8 — хороший, развёрнутый ответ с большинством ключевых пунктов.
6. 9-10 — отличный, полный ответ со всеми ключевыми пунктами и примерами.
7. Укажи для каждого студента слабые зоны (что нужно подтянуть).
8. Дай краткий конструктивный отзыв.
9. Объясни, ГДЕ ИМЕННО студент допустил ошибку и ПОЧЕМУ ответ неполный.
10. Дай ПРАВИЛЬНЫЙ РАЗВЁРНУТЫЙ ответ на вопрос.
11. Укажи КОНКРЕТНЫЕ ТЕМЫ, которые студенту нужно повторить.

Ответь СТРОГО JSON:
{"results": {"Студент_ID": {"score": N, "feedback": "краткий отзыв", "explanation": "подробное объяснение ошибок студента", "correct_answer": "правильный ответ на вопрос", "weak_areas": ["зона1", "зона2"], "topics_to_review": ["тема1 для повторения", "тема2 для повторения"]}}}""" % [question, key_points_str, answers_text]

	var req := HTTPRequest.new()
	req.name = "EvaluationRequest"
	add_child(req)
	req.timeout = 30.0  # Больше времени для оценки

	var url := ""
	var headers: Array = []
	var body_json := ""

	if _current_provider == PROVIDER_GROQ:
		url = API_URL
		headers = _get_headers()
		var body_dict := {
			"model": MODEL,
			"messages": [
				{"role": "system", "content": "Ты отвечаешь ТОЛЬКО валидным JSON. Никакого другого текста."},
				{"role": "user", "content": prompt},
			],
			"temperature": 0.3,
			"max_tokens": 2000,
		}
		body_json = JSON.stringify(body_dict)
	else:
		url = "%s%s:generateContent?key=%s" % [GOOGLE_URL_BASE, GOOGLE_MODEL, GOOGLE_KEY]
		headers = ["Content-Type: application/json"]
		var body_dict := {
			"contents": [{"parts": [{"text": prompt + "\n\nОтветь ТОЛЬКО JSON."}]}],
			"generationConfig": {
				"temperature": 0.3,
				"maxOutputTokens": 2000,
				"responseMimeType": "application/json"
			}
		}
		body_json = JSON.stringify(body_dict)

	var error := req.request(url, headers, HTTPClient.METHOD_POST, body_json)
	if error != OK:
		req.queue_free()
		print("[GeminiAPI] Ошибка запуска запроса (Оценка): код %d" % error)
		if not is_retry:
			print("[GeminiAPI] Пробуем сменить провайдера и повторить запрос оценки...")
			_current_provider = PROVIDER_GOOGLE if _current_provider == PROVIDER_GROQ else PROVIDER_GROQ
			evaluate_answers(question, key_points, answers_dict, true)
			return
		var fallback := _generate_fallback_scores(answers_dict)
		answers_evaluated.emit(fallback)
		return

	var response = await req.request_completed
	var result_code: int = response[0]
	var response_code: int = response[1]
	var response_body: PackedByteArray = response[3]
	req.queue_free()

	if result_code != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[GeminiAPI] Ошибка оценки: код %d, тело: %s" % [response_code, response_body.get_string_from_utf8()])
		if not is_retry:
			print("[GeminiAPI] Пробуем сменить провайдера и повторить запрос оценки...")
			_current_provider = PROVIDER_GOOGLE if _current_provider == PROVIDER_GROQ else PROVIDER_GROQ
			evaluate_answers(question, key_points, answers_dict, true)
			return
		
		var fallback := _generate_fallback_scores(answers_dict)
		answers_evaluated.emit(fallback)
		return

	var resp_text := _parse_response_universal(response_body)
	if resp_text == "":
		var fallback := _generate_fallback_scores(answers_dict)
		answers_evaluated.emit(fallback)
		return

	# Парсим JSON с результатами
	var json_text := resp_text.strip_edges()
	if json_text.begins_with("```"):
		json_text = json_text.replace("```json", "").replace("```", "").strip_edges()

	var start_idx := json_text.find("{")
	var end_idx := json_text.rfind("}")
	if start_idx == -1 or end_idx == -1:
		var fallback := _generate_fallback_scores(answers_dict)
		answers_evaluated.emit(fallback)
		return
	json_text = json_text.substr(start_idx, end_idx - start_idx + 1)

	var json := JSON.new()
	if json.parse(json_text) != OK:
		print("[GeminiAPI] JSON parse error в оценке: %s" % json.get_error_message())
		var fallback := _generate_fallback_scores(answers_dict)
		answers_evaluated.emit(fallback)
		return

	var data: Dictionary = json.data
	var results: Dictionary = data.get("results", data)

	# Конвертируем ключи "Студент_ID" обратно в peer_id
	var final_results: Dictionary = {}
	for key in results:
		var id_str := str(key).replace("Студент_", "")
		var peer_id := int(id_str) if id_str.is_valid_int() else 0
		if peer_id > 0 and results[key] is Dictionary:
			final_results[peer_id] = {
				"score": int(results[key].get("score", 5)),
				"feedback": str(results[key].get("feedback", "Оценка недоступна")),
				"weak_areas": results[key].get("weak_areas", []),
				"explanation": str(results[key].get("explanation", "")),
				"correct_answer": str(results[key].get("correct_answer", "")),
				"topics_to_review": results[key].get("topics_to_review", [])
			}

	# Проверяем, что все студенты получили оценки
	for peer_id_str in answers_dict:
		var pid := int(peer_id_str)
		if not final_results.has(pid):
			final_results[pid] = {"score": 5, "feedback": "Автоматическая оценка", "weak_areas": [], "explanation": "", "correct_answer": "", "topics_to_review": []}

	print("[GeminiAPI] ✅ Оценено %d ответов" % final_results.size())
	answers_evaluated.emit(final_results)


## Запасные оценки, если ИИ недоступен
func _generate_fallback_scores(answers_dict: Dictionary) -> Dictionary:
	var results: Dictionary = {}
	for peer_id_str in answers_dict:
		var pid := int(peer_id_str)
		var answer_text: String = str(answers_dict[peer_id_str]).strip_edges()
		# Простая эвристика: длина ответа
		var score: int = 5
		if answer_text.length() < 10:
			score = 2
		elif answer_text.length() < 30:
			score = 4
		elif answer_text.length() < 100:
			score = 6
		else:
			score = 7
		results[pid] = {
			"score": score,
			"feedback": "Автоматическая оценка (ИИ недоступен). Баллы за объём ответа.",
			"weak_areas": []
		}
	return results


# ==============================================================================
# Генерация плана изучения (Study Plan)
# ==============================================================================

## Генерирует план изучения на основе слабых зон студента
func generate_study_plan(weak_zones: Array, weak_topics: Array, recent_mistakes: Array, is_retry: bool = false) -> void:
	print("[GeminiAPI] 📚 Генерирую план изучения...")

	var zones_str := ", ".join(weak_zones) if not weak_zones.is_empty() else "нет данных"
	var topics_str := ", ".join(weak_topics) if not weak_topics.is_empty() else "нет данных"
	var mistakes_str := ""
	for m in recent_mistakes:
		mistakes_str += "- Вопрос: %s | Ответ: %s | Балл: %s/10\n" % [
			str(m.get("question", "?")),
			str(m.get("answer", "?")),
			str(m.get("score", "?"))
		]
	if mistakes_str == "":
		mistakes_str = "нет данных"

	var prompt := """Ты — опытный репетитор. На основе данных об ошибках студента составь ПЕРСОНАЛЬНЫЙ ПЛАН ИЗУЧЕНИЯ.

СЛАБЫЕ ЗОНЫ студента: %s
СЛАБЫЕ ТЕМЫ (низкие баллы): %s

ПОСЛЕДНИЕ ОШИБКИ:
%s

Составь план из 3-5 пунктов. Каждый пункт должен содержать:
1. Название темы для изучения
2. Что конкретно нужно выучить/повторить
3. Практическое задание для закрепления

Ответь СТРОГО JSON:
{"plan": [{"topic": "тема", "description": "что выучить", "exercise": "задание для практики"}], "summary": "краткое резюме для студента"}""" % [zones_str, topics_str, mistakes_str]

	var req := HTTPRequest.new()
	req.name = "StudyPlanRequest"
	add_child(req)
	req.timeout = 30.0

	var url := ""
	var headers: Array = []
	var body_json := ""

	if _current_provider == PROVIDER_GROQ:
		url = API_URL
		headers = _get_headers()
		var body_dict := {
			"model": MODEL,
			"messages": [
				{"role": "system", "content": "Ты отвечаешь ТОЛЬКО валидным JSON. Никакого другого текста."},
				{"role": "user", "content": prompt},
			],
			"temperature": 0.5,
			"max_tokens": 2000,
		}
		body_json = JSON.stringify(body_dict)
	else:
		url = "%s%s:generateContent?key=%s" % [GOOGLE_URL_BASE, GOOGLE_MODEL, GOOGLE_KEY]
		headers = ["Content-Type: application/json"]
		var body_dict := {
			"contents": [{"parts": [{"text": prompt + "\n\nОтветь ТОЛЬКО JSON."}]}],
			"generationConfig": {
				"temperature": 0.5,
				"maxOutputTokens": 2000,
				"responseMimeType": "application/json"
			}
		}
		body_json = JSON.stringify(body_dict)

	var error := req.request(url, headers, HTTPClient.METHOD_POST, body_json)
	if error != OK:
		req.queue_free()
		print("[GeminiAPI] Ошибка запуска запроса (План): код %d" % error)
		if not is_retry:
			print("[GeminiAPI] Пробуем сменить провайдера и повторить запрос плана...")
			_current_provider = PROVIDER_GOOGLE if _current_provider == PROVIDER_GROQ else PROVIDER_GROQ
			generate_study_plan(weak_zones, weak_topics, recent_mistakes, true)
			return
		study_plan_ready.emit({"plan": [], "summary": "Не удалось сгенерировать план (ошибка сети: %d)" % error})
		return

	var response = await req.request_completed
	var result_code: int = response[0]
	var response_code: int = response[1]
	var response_body: PackedByteArray = response[3]
	req.queue_free()

	if result_code != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[GeminiAPI] Ошибка генерации плана: код %d, тело: %s" % [response_code, response_body.get_string_from_utf8()])
		if not is_retry:
			print("[GeminiAPI] Пробуем сменить провайдера и повторить запрос плана...")
			_current_provider = PROVIDER_GOOGLE if _current_provider == PROVIDER_GROQ else PROVIDER_GROQ
			generate_study_plan(weak_zones, weak_topics, recent_mistakes, true)
			return
		
		study_plan_ready.emit({"plan": [], "summary": "Не удалось сгенерировать план (ошибка API: %d)" % response_code})
		return

	var resp_text := _parse_response_universal(response_body)
	if resp_text == "":
		study_plan_ready.emit({"plan": [], "summary": "Пустой ответ от ИИ"})
		return

	# Парсим JSON
	var json_text := resp_text.strip_edges()
	if json_text.begins_with("```"):
		json_text = json_text.replace("```json", "").replace("```", "").strip_edges()

	var start_idx := json_text.find("{")
	var end_idx := json_text.rfind("}")
	if start_idx == -1 or end_idx == -1:
		study_plan_ready.emit({"plan": [], "summary": "Не удалось распарсить план"})
		return
	json_text = json_text.substr(start_idx, end_idx - start_idx + 1)

	var json := JSON.new()
	if json.parse(json_text) != OK:
		study_plan_ready.emit({"plan": [], "summary": "JSON parse error"})
		return

	var data: Dictionary = json.data
	var plan_result := {
		"plan": data.get("plan", []),
		"summary": str(data.get("summary", "План изучения сформирован"))
	}
	print("[GeminiAPI] ✅ План изучения готов (%d пунктов)" % plan_result["plan"].size())
	study_plan_ready.emit(plan_result)
