/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Петрова Татьяна
 * Дата: 26.11.2024
*/

-- Пример фильтрации данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits) 
        AND rooms < (SELECT rooms_limit FROM limits) 
        AND balcony < (SELECT balcony_limit FROM limits) 
        AND ceiling_height < (SELECT ceiling_height_limit_h FROM limits) 
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

WITH limits AS (
SELECT
	PERCENTILE_DISC(0.99) WITHIN GROUP (
	ORDER BY total_area) AS total_area_limit,
	PERCENTILE_DISC(0.99) WITHIN GROUP (
	ORDER BY rooms) AS rooms_limit,
	PERCENTILE_DISC(0.99) WITHIN GROUP (
	ORDER BY balcony) AS balcony_limit,
	PERCENTILE_DISC(0.99) WITHIN GROUP (
	ORDER BY ceiling_height) AS ceiling_height_limit_h,
	PERCENTILE_DISC(0.01) WITHIN GROUP (
	ORDER BY ceiling_height) AS ceiling_height_limit_l
FROM
	real_estate.flats     
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
SELECT
	id
FROM
	real_estate.flats
WHERE
	total_area < (
	SELECT
		total_area_limit
	FROM
		limits)
	AND rooms < (
	SELECT
		rooms_limit
	FROM
		limits)
	AND balcony < (
	SELECT
		balcony_limit
	FROM
		limits)
	AND ceiling_height < (
	SELECT
		ceiling_height_limit_h
	FROM
		limits)
	AND ceiling_height > (
	SELECT
		ceiling_height_limit_l
	FROM
		limits)
    ),
caterory AS (
SELECT
	-- группируем данные по категории "Регион"
CASE
		WHEN f.city_id = '6X8I' THEN 'Санкт-Петербург'
		ELSE 'ЛенОбл'
	END AS category_city,
	-- группируем данные по категории "Время"
	CASE
		WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'Месяц'
		WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'Квартал'
		WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'Полгода'
		WHEN a.days_exposition >= 181 THEN 'Больше полугода'
		WHEN a.days_exposition IS NULL THEN 'Нет данных'
	END AS category_time_advert,
	(a.last_price::REAL / f.total_area::REAL)::NUMERIC(10,
	2) AS price_м²,
	fi.id
FROM
	filtered_id AS fi
LEFT JOIN real_estate.advertisement a
		USING(id)
LEFT JOIN real_estate.flats f
		USING(id)
WHERE
	f.type_id = 'F8EM' -- фильтруем объявления о продаже в городах
GROUP BY
	f.city_id,
	a.days_exposition,
	fi.id,
	a.last_price,
	f.total_area
  )
SELECT
	category_city,
	category_time_advert,
	count(category_time_advert) AS count_ads, -- кол-во объявлений
	(count(category_time_advert)::REAL / (
	SELECT
		count(id)::REAL
	FROM
		caterory) * 100)::NUMERIC(5,
	2) AS share_ads, -- считаем долю от всех объявлений
	avg(price_м²)::numeric(10, 2) AS avg_price_м², -- считаем среднюю стоимость метра квадратного
	avg(f.total_area)::numeric(6, 2) AS avg_area, -- считаем среднюю площадь
	PERCENTILE_DISC(0.5) WITHIN GROUP (
	ORDER BY f.rooms) AS rooms_mediana, -- считаем медиану кол-ва комнат
	PERCENTILE_DISC(0.5) WITHIN GROUP (
	ORDER BY f.balcony) AS balcony_mediana, -- считаем медиану кол-ва балконов
	PERCENTILE_DISC(0.5) WITHIN GROUP (
	ORDER BY f.ceiling_height)::numeric(2, 0) AS ceiling_height_mediana -- считаем медиану этажности
FROM
	caterory
LEFT JOIN real_estate.flats f using(id)
GROUP BY
	category_city,
	category_time_advert;


-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

WITH limits AS (
SELECT
	PERCENTILE_DISC(0.99) WITHIN GROUP (
ORDER BY
	total_area) AS total_area_limit,
	PERCENTILE_DISC(0.99) WITHIN GROUP (
ORDER BY
	rooms) AS rooms_limit,
	PERCENTILE_DISC(0.99) WITHIN GROUP (
ORDER BY
	balcony) AS balcony_limit,
	PERCENTILE_DISC(0.99) WITHIN GROUP (
ORDER BY
	ceiling_height) AS ceiling_height_limit_h,
	PERCENTILE_DISC(0.01) WITHIN GROUP (
ORDER BY
	ceiling_height) AS ceiling_height_limit_l
FROM
	real_estate.flats     
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
SELECT
	id
FROM
	real_estate.flats
WHERE
	total_area < (
	SELECT
		total_area_limit
	FROM
		limits)
	AND rooms < (
	SELECT
		rooms_limit
	FROM
		limits)
	AND balcony < (
	SELECT
		balcony_limit
	FROM
		limits)
	AND ceiling_height < (
	SELECT
		ceiling_height_limit_h
	FROM
		limits)
	AND ceiling_height > (
	SELECT
		ceiling_height_limit_l
	FROM
		limits)
    ),
-- рассчитываем показатели по опубликованным об-м
count_ads_published AS (
SELECT
	count(a.id) AS count_published_ads,
	-- считаем количество опубликованных объявлений
	EXTRACT(MONTH
FROM
	a.first_day_exposition) AS month_first_exposition,
	-- выделяем номер месяца из даты публикации объявления
	ROUND(SUM(a.last_price) / SUM(f.total_area)) AS avg_cost_м²_published,
	-- средняя стоимость квадратного метра для опубликованных объявлений
	avg(f.total_area)::NUMERIC(10,
	2) AS avg_area_published
	--средняя площадь квартир в объявлениях, которые опубликованы
FROM
	filtered_id AS fi
LEFT JOIN real_estate.advertisement a
		USING(id)
LEFT JOIN real_estate.flats f
		USING(id)
WHERE
	a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31' AND f.type_id = 'F8EM'
GROUP BY
	month_first_exposition
),
count_ads_removed AS (
SELECT
	count(a.id) AS count_removed_ads,
	-- считаем количество опубликованных объявлений
	EXTRACT(MONTH
FROM 
	a.first_day_exposition + a.days_exposition * INTERVAL '1 day') AS removed_month,
	-- выделяем номер месяца из даты снятия объявления
((count(a.id)::REAL / (
	SELECT
		count(id)
	FROM
		real_estate.advertisement a
	LEFT JOIN real_estate.flats f
			USING(id)
	WHERE
		first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'
		AND f.type_id = 'F8EM')::REAL) * 100)::NUMERIC(5,
	2) AS share_removed_ads,
	--доля снятых объявлений от общего количества
	ROUND(SUM(a.last_price) / SUM(f.total_area)) AS avg_cost_м²_removed,
	-- cредняя стоимость квадратного метра для объявление, которые были сняты
	avg(f.total_area)::NUMERIC(10,
	2) AS avg_area_removed
	--средняя площадь квартир в объявлениях, которые были сняты
FROM
	filtered_id AS fi
LEFT JOIN real_estate.advertisement a
		USING(id)
LEFT JOIN real_estate.flats f
		USING(id)
WHERE
	a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'
	AND f.type_id = 'F8EM'
	AND a.days_exposition IS NOT NULL
GROUP BY
	removed_month
)
SELECT
	month_first_exposition AS month_first_exposition,
	count_published_ads AS count_published_ads,
	count_removed_ads,
	share_removed_ads,
	RANK() OVER (
ORDER BY
	count_published_ads DESC) AS rank_published,
	--ранг активности опубликованных объявлений
	RANK() OVER (
ORDER BY
	count_removed_ads DESC) AS rank_removed,
	--ранг актирности снятых с продажи объявлений
	avg_cost_м²_published,
	-- средняя стоимость квадратного метра для опубликованных объявлений
	avg_cost_м²_removed,
	-- cредняя стоимость квадратного метра для объявление, которые были сняты
	avg_area_removed,
	--средняя площадь квартир в объявлениях, которые были сняты
	avg_area_published
	--средняя площадь квартир в объявлениях, которые опубликованы
FROM
	count_ads_published AS cap
FULL JOIN count_ads_removed AS car ON
	cap.month_first_exposition = car.removed_month
ORDER BY
	month_first_exposition
	--сортируем по месяцу публикации объявлений

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

WITH limits AS (
SELECT
	PERCENTILE_DISC(0.99) WITHIN GROUP (
ORDER BY
	total_area) AS total_area_limit,
	PERCENTILE_DISC(0.99) WITHIN GROUP (
ORDER BY
	rooms) AS rooms_limit,
	PERCENTILE_DISC(0.99) WITHIN GROUP (
ORDER BY
	balcony) AS balcony_limit,
	PERCENTILE_DISC(0.99) WITHIN GROUP (
ORDER BY
	ceiling_height) AS ceiling_height_limit_h,
	PERCENTILE_DISC(0.01) WITHIN GROUP (
ORDER BY
	ceiling_height) AS ceiling_height_limit_l
FROM
	real_estate.flats     
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
SELECT
	id
FROM
	real_estate.flats
WHERE
	total_area < (
	SELECT
		total_area_limit
	FROM
		limits)
	AND rooms < (
	SELECT
		rooms_limit
	FROM
		limits)
	AND balcony < (
	SELECT
		balcony_limit
	FROM
		limits)
	AND ceiling_height < (
	SELECT
		ceiling_height_limit_h
	FROM
		limits)
	AND ceiling_height > (
	SELECT
		ceiling_height_limit_l
	FROM
		limits)
    ),
advertisement_data AS (
SELECT
	f.city_id,
	count(fi.id) AS total_ads,
	(count(fi.id) FILTER(
	WHERE a.days_exposition IS NOT NULL)::REAL / count(fi.id)::REAL)::NUMERIC(7,
	2) * 100 AS share_removed_ads,
	-- доля закрытых объявлений
	avg(a.last_price::REAL / f.total_area::REAL)::NUMERIC(10,
	2) AS avg_price_м²,
	-- считаем стоимость квадратного метра
	avg(total_area)::NUMERIC(7,
	2) AS avg_area, -- средняя площадь
	avg(a.days_exposition)::NUMERIC(7,
	0) AS avg_days_exposition -- средняя длительность
FROM
	filtered_id AS fi
LEFT JOIN real_estate.advertisement a
		USING(id)
LEFT JOIN real_estate.flats f
		USING(id)
WHERE
	f.city_id <> '6X8I'
	-- фильтруем объявления о продаже в ЛенОбл
GROUP BY
	f.city_id
  )
 SELECT
	c.city, -- название города
	total_ads, -- всего объявлений
	share_removed_ads, -- доля закрытых объявлений
	avg_price_м², -- средняя стоимость м²
	avg_area, -- средняя площадь квартир
	avg_days_exposition -- средняя длительность
FROM
	advertisement_data
LEFT JOIN real_estate.city c
		USING(city_id)
ORDER BY total_ads DESC, avg_price_м² DESC -- сортируем ко количеству объявлений и стоимоти квадратного метра по убыванию
LIMIT 15; -- делаю топ-15