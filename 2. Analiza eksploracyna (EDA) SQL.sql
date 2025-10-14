
### 1. analiza spójności cen konkretnych produktów

# sprawdzam czy występuje zmienność ceny w zależności od:

# 1.wpływ czasu - miesiąca, dnia tygodnia
SELECT
    coffee_name,
    Monthsort,
    Weekdaysort,
    COUNT(*) AS total_sales,
    MIN(money) AS min_price,
    MAX(money) AS max_price
FROM
    `sales.sales`
GROUP BY
    coffee_name,
    Monthsort,
    Weekdaysort
ORDER BY
    coffee_name, Monthsort, Weekdaysort;

--- występują rozbieżności w cenach tych samych produktów, 
--- brak widocznych zależności zróżnicowania cen produktu od miesiąca czy dnia tygodnia.

# 2. wpływ godziny
SELECT
    coffee_name,
    hour_of_day, -- Największa granularność czasu
    COUNT(*) AS total_sales,
    MIN(money) AS min_price,
    MAX(money) AS max_price
FROM
    `sales.sales`
GROUP BY
    coffee_name,
    hour_of_day
ORDER BY
    coffee_name, hour_of_day;

---brak widocznych zależności zróżnicowania cen produktu od godziny sprzedaży

# 3. wpływ Time_of_Day
SELECT
    coffee_name,
    Time_of_Day,
    COUNT(*) AS total_sales,
    MIN(money) AS min_price,
    MAX(money) AS max_price,
    -- Obliczenie średniej ceny dla danego produktu w danej porze dnia
    ROUND(AVG(money), 2) AS avg_time_of_day_price
FROM
    `sales.sales` -- Używamy tabeli 'sales_clean'
GROUP BY
    coffee_name,
    Time_of_Day
ORDER BY
    coffee_name,
    Time_of_Day,
    total_sales DESC;

--- brak widocznych zależności zróżnicowania cen produktu od pory dnia

# 4. wpływ cash_type 
SELECT
    coffee_name,
    cash_type,
    COUNT(*) AS total_sales,
    MIN(money) AS min_price,
    MAX(money) AS max_price,
    -- Obliczenie średniej ceny dla danego produktu i metody płatności
    ROUND(AVG(money), 2) AS avg_payment_price
FROM
    `sales.sales`
GROUP BY
    coffee_name,
    cash_type
ORDER BY
    coffee_name,
    cash_type;

--- brak widocznych zależności zróżnicowania cen produktu od formy zapłaty

--- wnioski: brak widocznych jednoczynnikowych zależności w całym zakresie danych. Zależność może być od kilku czynników albo są inne czynniki poza analizowanymi, być może z poza danych z bazy. Możliwe też są zmiany np inflacyjne lub inne okresowe w zależności od miesiąca.

# sprawdzam ręcznie na przykładzie jednego typu kawy
SELECT
      *
FROM `sales.sales`
WHERE coffee_name = 'Espresso'
ORDER BY datetime;

---obserwacje: 
---ceny espresso przy płatności kartą nie podlegały zmianom godzinowym ani od dnia tygodnia.
---ceny zmieniały się z czasem - najpierw były 24,00 - 23,02 - 18.12 - 21,06. Zmiany cen nie zawsze były związane ze zmianą miesiąca - 05 Lip - 23,02$, 18.07 - 18,12$. 
---kwoty przy płatnościach gotówką były zawsze wyższe od płatności gotówką o ok 1$, zawsze w wartościach całkowitych. 
---kwoty przy płatności gotówką zawsze były te same w obrębie aktualnego cennika więc nie były to napiwki uznaniowe
---wnioski: 
---cennik w kawiarni zmieniał się z czasem, 
---cena była wyższa kiedy klient płacił gotówką.

# sprawdzam kod analogiczny do pierwszego sprawdzenia ale ograniczony do kwietnia i płatności kartą
SELECT
    coffee_name,
    cash_type,
    Monthsort,
    COUNT(*) AS total_sales,
    MIN(money) AS min_price,
    MAX(money) AS max_price,
    -- Obliczenie średniej ceny dla danego produktu i metody płatności
    ROUND(AVG(money), 2) AS avg_payment_price
FROM
    `sales.sales`
GROUP BY
    coffee_name,
    cash_type,
    Monthsort
HAVING
    Monthsort = 4 AND cash_type = 'card'
ORDER BY
    coffee_name,
    cash_type,
    Monthsort;

---obserwacja:
---espresso miało stabilne ceny w kwietniu rozliczane kartą, inne typy kawy nie

# sprawdzam ręcznie inny typ kawy - Americano

    SELECT *
    FROM `sales.sales`
    where coffee_name = 'Americano'
    ORDER BY datetime;

---obserwacje
---analogicznie do espresso, ceny są zmienne w zależności od daty, kwota gotówką jest zawsze wyższa od karty
---zmiany cennika wystąpiły w innym monencie niż w przypadku espresso. 
---wnioski
---zmiany cen poszczególnych produktów nie są przeprowadzane w tym samym czasie
---kwota przy płatności gotówką jest wyższa niż przy płatności kartą o ponad 1$
---kwota przy płatności gotówką jest zaokrąglona do liczby całkowitej

---wnioski końcowe ws spójności cen w bazie
---cena produktu zależy od dwóch zmiennych: daty (występowały okresowe zmiany cennika) oraz sposobu płatności (płatność gotówką oznaczała wyższą kwotę - ok +1$, wartości całkowite)
---zmiany cen dla różnych produktów odbywały się w różnych datach
---ceny różnych produktów są niezależne od godziny, dnia tygodnia, numeru karty, ilości produktów w jednej transakcji.

### 2. grupuję pojedyńcze rekordy w transakcje zawierające kilka produktów
---Prawdopodobnym jest że jedna osoba może kupić kilka produktów przy tej samej wizycie. Dla analizy wielkości sprzedaży, sprzedaży wiązanych, analizy wielkości koszyka warto wyznaczyć ID transakcji. 
---Dla określenia które wiersze należą do tej samej transakcji kluczowy jest timestamp a więc ‘datetime’. Teoretycznie może też być transakcja w tym samym czasie co można zróżnicować po ‘card’ - w przypadku płatności kartą.
---założenia: 
----klienci z kartą: card is not null + ta same wartości datetime i card
----klienci bez karty: card is null + te same wartosci datetime i cash_type
---W wyniku kilku testów najlepiej sprawdziła się metoda pogrupowania transakcji wg czasu, ustaliłem 300 sekund jako kompromis między zbyt dużą granularnością a zbyt dużym zakresem

WITH RankedTransactions AS (
    -- 1. Przygotowanie danych i stworzenie unikalnego klucza klienta
    SELECT
        *,
        CASE
            WHEN card IS NOT NULL THEN card
            ELSE 'CASH_' || cash_type
        END AS customer_key
    FROM
        `sales.sales_clean`
),
TimeDifferences AS (
    -- 2. Obliczenie różnicy czasowej między kolejnymi transakcjami tego samego klienta
    SELECT
        *,
        LAG(datetime, 1) OVER (PARTITION BY customer_key ORDER BY datetime) AS previous_datetime,
        TIMESTAMP_DIFF(datetime, LAG(datetime, 1) OVER (PARTITION BY customer_key ORDER BY datetime), SECOND) AS time_diff_seconds
    FROM
        RankedTransactions
),
OrderStarts AS (
    -- 3. Identyfikacja początku nowego zamówienia (tworzenie order_group_id)
    SELECT
        *,
        -- Licznik kumulatywny, który zmienia wartość, gdy upłynie 300 sekund
        COUNTIF(time_diff_seconds IS NULL OR time_diff_seconds >= 300)
            OVER (PARTITION BY customer_key ORDER BY datetime) AS order_group_id
    FROM
        TimeDifferences
)
-- 4. OBLICZENIE FINALNYCH WARTOŚCI I PRZYPISANIE DO KAŻDEGO WIERSZA
SELECT
    t.*, -- Wybiera wszystkie oryginalne kolumny z OrderStarts
   
    -- Tworzenie unikalnego ID dla każdego wiersza
    FORMAT('%t', FIRST_VALUE(t.datetime)
        OVER (PARTITION BY t.customer_key, t.order_group_id ORDER BY t.datetime)) || '_' || t.customer_key AS final_order_id,
   
    -- Agregacja liczby produktów na poziomie order_id (funkcja okienkowa)
    COUNT(*)
        OVER (PARTITION BY t.customer_key, t.order_group_id) AS total_products_in_order,
       
    -- Agregacja łącznej wartości zamówienia (funkcja okienkowa)
    SUM(t.money)
        OVER (PARTITION BY t.customer_key, t.order_group_id) AS total_value_of_order
       
FROM
    OrderStarts t
ORDER BY
    t.datetime;

SELECT
      DISTINCT(order_id)
FROM `sales.sales_transactions`
--- kwerenda łączy dość sporo rekordów, tworząc 2984 transakcji z 3636 rekordów
--- wyrywkowo sprawdzone są wiarygodnie powiązane, przy kartach można mieć pewność, przy gotówce duże prawdopodobieństwo. Ewentualne błedy w cash nie powinny mieć istotnego znaczenia przy małym udziale tego typu płatności

--- stworzyłem nowa zmienną order_id która ma za zadanie pogrupować wiersze z poszczególnymi produktami w wieloproduktowe transakcje - może być przydatne do analizy koszyka.

### 3. tworzę sales_transactions

--- tabela zawiera kolumny które grupują rekordy w transakcje

CREATE OR REPLACE TABLE
    `sales.sales_transactions`
AS
WITH RankedTransactions AS (
    -- 1. Przygotowanie danych i stworzenie unikalnego klucza klienta
    SELECT
        t.*,
        -- Tworzenie customer_key (używa oryginalnych kolumn cash_type i card)
        CASE
            WHEN t.card IS NOT NULL THEN t.card
            ELSE 'CASH_' || t.cash_type
        END AS customer_key
    FROM
        `sales.sales_clean` t -- Używamy czystej tabeli 'sales_clean'
),
TimeDifferences AS (
    -- 2. Obliczenie różnicy czasowej między kolejnymi transakcjami tego samego klienta
    SELECT
        rt.*,
        LAG(rt.datetime, 1) OVER (PARTITION BY rt.customer_key ORDER BY rt.datetime) AS previous_datetime,
        -- Różnica w sekundach (300 sekund = 5 minut)
        TIMESTAMP_DIFF(rt.datetime, LAG(rt.datetime, 1) OVER (PARTITION BY rt.customer_key ORDER BY rt.datetime), SECOND) AS time_diff_seconds
    FROM
        RankedTransactions rt
),
OrderStarts AS (
    -- 3. Identyfikacja początku nowego zamówienia (Tworzenie order_group_id)
    SELECT
        td.*,
        -- Próg: 300 SEKUND
        COUNTIF(td.time_diff_seconds IS NULL OR td.time_diff_seconds >= 300)
            OVER (PARTITION BY td.customer_key ORDER BY td.datetime) AS order_group_id
    FROM
        TimeDifferences td
)
-- 4. Budowa finalnej tabeli, dołączająca tylko nowe kolumny transakcyjne
SELECT
    t.* EXCEPT(customer_key, previous_datetime, time_diff_seconds, order_group_id), -- Usuwamy kolumny tymczasowe
   
    -- FINALNE KOLUMNY TRANSAKCYJNE (AGREGACJA NA NOWO UTWORZONEJ GRUPIE)
   
    -- Finalny identyfikator zamówienia
    FORMAT('%t', FIRST_VALUE(t.datetime)
        OVER (PARTITION BY t.customer_key, t.order_group_id ORDER BY t.datetime)) || '_' || t.customer_key AS order_id,
   
    -- Agregacja liczby produktów na poziomie order_id
    COUNT(*)
        OVER (PARTITION BY t.customer_key, t.order_group_id) AS total_products_in_order,
       
    -- Agregacja łącznej wartości zamówienia
    SUM(t.money)
        OVER (PARTITION BY t.customer_key, t.order_group_id) AS total_value_of_order
       
FROM
    OrderStarts t;

--- stworzona nowa tabela sales_transaction zawierająca zmienne dotyczące transakcji wieloproduktowych.
