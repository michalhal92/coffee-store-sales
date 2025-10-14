-----#####----- 1. Przygotowanie danych SQL -----#####-----

# 1. wczytanie danych: plik był w xlsx którego nie mogę wgrać do Big Query importem, musiałem go wczytać przez Google Sheets. 
      
--- liczba rekordów 3636

--- sprawdzenie tabeli i typów danych w kolumnach - money wydaje się liczbowa, w bazie jest string, do sprawdzenia

# 2. sprawdzenie przykładowych danych
SELECT *
FROM `sales.sales`
LIMIT 5;
--- struktura dancyh dość jasna i intuicyjna

# 3. sprawdzenie rozpiętości czasowej danych

# daty
SELECT
      date
FROM
      `sales.sales`
ORDER BY
      date
LIMIT 10;

--- najstarsze daty od 2024-03-01

SELECT
      date
FROM
      `sales.sales`
ORDER BY
      date DESC
LIMIT 10;

---najnowsze daty do 2025-03-22

# godziny
SELECT
      EXTRACT(TIME FROM datetime) as order_time
FROM
     `sales.sales`
ORDER BY
      order_time
LIMIT 10;

--- najwcześniejsze godziny to 6:50

SELECT
      EXTRACT(TIME FROM datetime) as order_time
FROM
     `sales.sales`
ORDER BY
      order_time DESC
LIMIT 10;

--- najpóźniejsze godziny to 22:59

--- wnioski: baza obejmuje daty od 2024-03-01 do 2025-03-22, godziny od 6:50 do 23:00 

## 4. sprawdzenie nulli
SELECT
    COUNTIF(date IS NULL) AS nulls_in_date,
    COUNTIF(datetime IS NULL) AS nulls_in_datetime,
    COUNTIF(hour_of_day IS NULL) AS nulls_in_hour_of_day,
    COUNTIF(cash_type IS NULL) AS nulls_in_cash_type,
    COUNTIF(card IS NULL) AS nulls_in_card,
    COUNTIF(money IS NULL) AS nulls_in_money,
    COUNTIF(coffee_name IS NULL) AS nulls_in_coffee_name,
    COUNTIF(Time_of_Day IS NULL) AS nulls_in_Time_of_Day,
    COUNTIF(Weekday IS NULL) AS nulls_in_Weekday,
    COUNTIF(Month_name IS NULL) AS nulls_in_Month_name,
    COUNTIF(Weekdaysort IS NULL) AS nulls_in_Weekdaysort,
    COUNTIF(Monthsort IS NULL) AS nulls_in_Monthsort
FROM `coffee-store-sales.sales.sales`;

--- nulle są tylko w kolumnie card

# sprawdzenie transakcji z card is null
SELECT *
FROM `sales.sales`
WHERE card IS NULL;


--- wygląda że wszystkie nulle kolumny card są z uwagi na płatność cash

# sprawdzenie czy są jakieś transakcje które nie mają numeru karty ale nie są gotówkowe
SELECT *
FROM `sales.sales`
WHERE card IS NULL AND cash_type != 'cash';

--- wszystkie transakcje kartą mają przyporządkowany zanonimizowany numer karty - kolumna card

### 5. unikalne wartości w kolumnach kategorialnych

-- 1. hour_of_day
SELECT
    hour_of_day,
    COUNT(hour_of_day) AS total_transactions
FROM
    `sales.sales`
GROUP BY
    hour_of_day
ORDER BY
    hour_of_day;

--- hour_of_day: od 6 do 22

--- o godzinie 6 jest tylko 5 transakcji, to intrygujące,
# sprawdzam transakcje o godzinie 6
SELECT *
FROM `sales.sales`
WHERE hour_of_day = 6;

--- przed 7:00 jest tylko 5 transakcji z lutego i marca 2025, 4 z nich na tego samego klienta. 
--- Czy kawiarnia jest na pewno czynna od 7:00 czy może od 6.50? Być może pracownicy piją ewidencjonowaną kawę przed otwarciem albo otwierają wcześniej?

-- 2. cash_type
SELECT
    cash_type,
    COUNT(cash_type ) AS total_transactions
FROM
    `sales.sales`
GROUP BY
    cash_type
ORDER BY
    cash_type;

--- cash_type: card / cash, zdecydowanie dominuje karta

-- 3. coffee_name
SELECT
    coffee_name,
    COUNT(coffee_name ) AS total_transactions
FROM
    `sales.sales`
GROUP BY
    coffee_name
ORDER BY
    total_transactions DESC;

--- coffee name: 8 różnych kaw, 3 najpopularniejsze ilościowo: Americano with Milk, Latte, Americano

-- 4. Time_of_Day
SELECT
    Time_of_Day,
    COUNT(Time_of_Day ) AS total_transactions
FROM
    `sales.sales`
GROUP BY
    Time_of_Day
ORDER BY
    Time_of_Day;

--- Time_of_Day: Morning, Afternoon, Night

# sprawdzam jakie godziny wchodzą w poszczególne pory dnia
SELECT
    Time_of_Day,
    hour_of_day,
    COUNT(*) AS total_count
FROM
    `sales.sales`
GROUP BY
    Time_of_Day,
    hour_of_day
ORDER BY
    hour_of_day,
    Time_of_Day;

---pory dnia obejmują godziny:
---morning 6-11
---afternoon 12-16
---night 17-22

---jest jedna wartość potencjalnie niepoprawna: godzina 16 przypisana do night, są więc potencjalne niezgodności w danych, należy to sprawdzić w tej i innych zmiennych później

-- 5. Weekday
SELECT
    Weekday,
    COUNT(Weekday) AS total_transactions
FROM
    `sales.sales`
GROUP BY
    Weekday
ORDER BY
    Weekday;

---Weekday: wszystkie 7

-- 6. Month_name
SELECT
    Month_name,
    COUNT(Month_name) AS total_transactions
FROM
    `sales.sales`
GROUP BY
    Month_name
ORDER BY
    Month_name;

--- Month_name: wszystkie 12

-- 7. Weekdaysort
SELECT
    Weekdaysort,
    COUNT(Weekdaysort) AS total_transactions
FROM
    `sales.sales`
GROUP BY
    Weekdaysort
ORDER BY
    Weekdaysort;

--- Weekdaysort: wszystkie 12

-- 8. Monthsort
SELECT
    Monthsort,
    COUNT(Monthsort) AS total_transactions
FROM
    `sales.sales`
GROUP BY
    Monthsort
ORDER BY
    Monthsort;

--- Monthsort: wszystkie 12

### 6. spójność Weekdaysort, Monthsort, hour_of_day

### sprawdzam spójność Weekdaysort, Monthsort, hour_of_day z odpowiednio: Weekday, Month i datetime?

# sprawdzam Weekdaysort
SELECT
    Weekday,
    COUNT(DISTINCT Weekdaysort) AS unique_sort_count
FROM
    `sales.sales`
GROUP BY
    Weekday;

--- pełna spójność Weekdaysort z Weekday

# sprawdzam Monthsort
SELECT
    Month_name,
    COUNT(DISTINCT Monthsort) AS unique_sort_count
FROM
    `sales.sales`
GROUP BY
    Month_name;

--- pełna spójność  Monthsort z Month_name

# sprawdzam hour_of_day 
SELECT
        EXTRACT(HOUR FROM datetime) AS hour,
        hour_of_day,
        COUNT(hour_of_day)
FROM `sales.sales`
GROUP BY hour, hour_of_day
ORDER BY hour, hour_of_day;

SELECT
    datetime,
    hour_of_day,
    EXTRACT(HOUR FROM datetime) AS extracted_hour
FROM
    `sales.sales`
WHERE
    hour_of_day != EXTRACT(HOUR FROM datetime);

---jeden rekord jest niespójny hour_of_day z datetime, prawdopodobnie z uwagi na błędne zaokrąglenie. 
---kolumna datetime jest źródłowa więc traktujemy ją jako poprawną, hour_of_day jest wtórna więc błędna. 
---To tylko jeden rekord więc mały % błędu ale można poprawić. 
---poprawię niespójną godzinę przy tworzeniu nowej oczyszczonej tabeli na podstawie źródłowej, 
---kodem:

---EXTRACT(HOUR FROM datetime) AS hour_of_day,

### 7. money jako string - konwersja
---w kolumnie money mamy string, chcemy zrobić tutaj wartość liczbową. 

---Dane są z przedrostkiem R, prawdopodobnie walutą. Do wartości niecałkowitych używany jest ’,’ zamiast ‘.’. Te dwie rzeczy musimy zmienić aby zmienić rodzaj danych. Przekonwertuję money na float64 z uwagi na wartości niecałkowite, format numeric nie jest konieczny z uwagi na zbędną dokładności na najwyższym poziomie, float64 jest łatwiejszy do przetwarzania i zgodny z pythonem. kod do implementacji przy tworzeniu nowej tabeli:

---CAST(REPLACE(REPLACE(money, 'R', ''), ',', '.') AS float64) AS money_numeric

### 8. tworzę sales_clean

# tworzę nową oczyszczoną tabelę sales_clean
CREATE OR REPLACE TABLE
    `sales.sales_clean`
AS
SELECT
    -- Wybieramy wszystkie kolumny poza modyfikowanymi
    t.* EXCEPT(money, hour_of_day),
   
    -- KOREKTA 1: Poprawiony hour_of_day
    EXTRACT(HOUR FROM t.datetime) AS hour_of_day,
   
    -- KOREKTA 2: Oczyszczona wartość money
    CAST(REPLACE(REPLACE(t.money, 'R', ''), ',', '.') AS FLOAT64) AS money
FROM
    `sales.sales` AS t;

# sprawdzam istnienie niespójości datetime - hour_of_day
SELECT
    datetime,
    hour_of_day,
    EXTRACT(HOUR FROM datetime) AS extracted_hour
FROM
    `sales.sales_clean`
WHERE
    hour_of_day != EXTRACT(HOUR FROM datetime);

--- brak niezgodności

# sprawdzam format kolumny money
SELECT *
FROM `sales.sales_clean`
LIMIT 10

--- format zmieniony

--- Stworzona oczyszczona tabela sales_clean, zidentyfikowane problemy zostały wyeliminowane. Będzie ona źródłem do dalszej transformacji i analizy.
