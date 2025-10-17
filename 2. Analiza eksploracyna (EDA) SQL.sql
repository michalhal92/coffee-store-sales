-----#####----- 2. Analiza eksploracyjna -----#####-----


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
    `sales.sales_clean`
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
    `sales.sales_clean`
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
    `sales.sales_clean`
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
    `sales.sales_clean`
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
FROM `sales.sales_clean`
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
    `sales.sales_clean`
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
    FROM `sales.sales_clean`
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
---W wyniku kilku testów najlepiej sprawdziła się metoda pogrupowania transakcji wg czasu, ustaliłem 300 sekund między timestampami jako kompromis między zbyt dużą granularnością a zbyt dużym zakresem

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
        OVER (PARTITION BY t.customer_key, t.order_group_id ORDER BY t.datetime)) || '_' || t.customer_key AS order_id,
   
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

### 4. Wskaźniki Efektywności i Czasu (AOV, Items Per Order, Sezonowość)
#Cel: Efektywność Operacyjna i Analiza Sezonowości
#Akcje: Obliczenie AOV, Items Per Order, Total Revenue i Total Orders w podziale na Month_name, Weekday, hour_of_day i cash_type.\

SELECT
    -- Wymiary czasowe i segmentacyjne
    Month_name,
    Monthsort,      
    Weekday,
    Weekdaysort,    
    Time_of_Day,
    hour_of_day,
    cash_type,      
    
    -- Wskaźniki ilościowe i wartościowe
    COUNT(DISTINCT order_id) AS total_orders,        -- Liczba UNIKALNYCH ZAMÓWIEŃ
    COUNT(*) AS total_items_sold,                 -- Całkowita liczba sprzedanych produktów (suma wierszy)
    SUM(total_value_of_order) AS total_revenue,      -- Całkowity przychód 
    
    -- Średnie wartości
    ROUND(AVG(total_value_of_order), 2) AS average_order_value, ---AOV
    ROUND(AVG(total_products_in_order), 2) AS units_per_transaction ---UPT

FROM
    `sales.sales_transactions`
GROUP BY
    1, 2, 3, 4, 5, 6, 7 
ORDER BY
    Monthsort, Weekdaysort, hour_of_day;

--- stworzona tabela pokazuje total_orders, total_items_sold, total revenue, AOV i UPT w podziale na miesiace, dni tygodnia,pory dnia i godziny
--- umożliwia to podstawową analizę sprzedaży w czasie

#Etap 5: Analiza Sprzedaży Wiązanej (MBA) 🧺
#Cel: Identyfikacja wzorców zakupowych.
#Akcja: Ustalenie najczęściej kupowanych par produktów (product_a, product_b) i ich częstotliwości (zgodnie z kodem zaproponowanym w mojej pierwszej odpowiedzi).

# sprawdzam jakie pary produktowe są najczęściej występujące

### ETAP 5: ANALIZA SPRZEDAŻY WIĄZANEJ (MBA) - NAJCZĘSTSZE PARY

SELECT
    t1.coffee_name AS product_a,
    t2.coffee_name AS product_b,
    COUNT(DISTINCT t1.order_id) AS co_occurrence_count -- Liczba transakcji, w których wystąpiły oba produkty
FROM
    `sales.sales_transactions` t1
JOIN
    `sales.sales_transactions` t2 --- samozłączenie
    ON t1.order_id = t2.order_id -- Warunek 1: Muszą być w tej samej transakcji
    AND t1.coffee_name < t2.coffee_name -- Warunek 2: Eliminacja duplikatów (A, B) i symetrycznych par (B, A)
GROUP BY 
    1, 2
ORDER BY
    co_occurrence_count DESC
LIMIT 10;

---- top 4 łączonych kaw to 2x warian kawy z mlekiem (Americano with Milk, Latte, Cappuccino, Hot Chocolate), 7/10 top par zawiera któryś wariant kawy z mlekiem

# obliczam wskaźniki Support, Confidencje, Lift

WITH TotalOrders AS (
    -- 1. Całkowita liczba unikalnych transakcji (N)
    SELECT 
        COUNT(DISTINCT order_id) AS total_count
    FROM 
        `sales.sales_transactions`
),
IndividualCounts AS (
    -- 2. Liczba transakcji dla każdego pojedynczego produktu: Count(A) i Count(B)
    SELECT 
        coffee_name, -- ZMIANA: product_name -> coffee_name
        COUNT(DISTINCT order_id) AS individual_count
    FROM 
        `sales.sales_transactions`
    GROUP BY 1
),
PairCoOccurrence AS (
    -- 3. Liczba transakcji zawierających parę produktów: Count(A i B)
    SELECT
        t1.coffee_name AS coffee_a, -- ZMIANA: product_name -> coffee_name
        t2.coffee_name AS coffee_b, -- ZMIANA: product_name -> coffee_name
        COUNT(DISTINCT t1.order_id) AS co_occurrence_count
    FROM
        `sales.sales_transactions` t1
    JOIN
        `sales.sales_transactions` t2
        ON t1.order_id = t2.order_id
        AND t1.coffee_name < t2.coffee_name -- ZMIANA: product_name -> coffee_name
    GROUP BY 1, 2
)
SELECT
    p.coffee_a,
    p.coffee_b,
    p.co_occurrence_count,
    
    -- 1. SUPPORT S(A^B)
    p.co_occurrence_count / t.total_count AS Support_AB,

    -- 2. CONFIDENCE C(A -> B)
    p.co_occurrence_count / cA.individual_count AS Confidence_A_to_B,

    -- 3. CONFIDENCE C(B -> A)
    p.co_occurrence_count / cB.individual_count AS Confidence_B_to_A,

    -- 4. LIFT
    (p.co_occurrence_count / t.total_count) 
    / ((cA.individual_count / t.total_count) * (cB.individual_count / t.total_count)) AS Lift

FROM
    PairCoOccurrence p
CROSS JOIN
    TotalOrders t
JOIN
    IndividualCounts cA ON p.coffee_a = cA.coffee_name -- ZMIANA: product_name -> coffee_name
JOIN
    IndividualCounts cB ON p.coffee_b = cB.coffee_name -- ZMIANA: product_name -> coffee_name
ORDER BY
    p.co_occurrence_count DESC
LIMIT 10;

--- z uwagi na stosunkowo małą ilość transakcji wieloproduktowych (ok 600 tj ok 20% wszystkich transakcji) trudno jest o wyznaczenie prostych wskaźników potwierdających zasadność tych par pod kątem cross-sellingu.
--- kawy są substytutami względem siebie, jeżeli chcielibyśmy zwiększać koszyk możemy podjąć dwie strategie 
---  1. rabat przy dwóch produktach - może zformalizować już istniejący wzorzec zakupowy i ułatwić przyszłą analizę (bezpośrednie grupowanie w faktyczne transakcje), ściągnąć klientów na spotkania stacjonarne zwiększając obrót kosztem zysku (lepsza rotacja, większa atrakcyjność dla klienta)
---  2. rozszerzenie asortymentu do cross-sellingu - niski LIFT między kawami sugeruje że budowanie faktycznego koszyka warto zrobić poprzez nowe produkty uzupełniające - np słodycze, przekąski, dania, napoje butelkowane na wynos

#Etap 6: Analiza Wartości i Lojalności Klienta (CLV/Frequency/CRR)
#Cel: Określenie, którzy klienci (głównie z kartą) generują największy przychód i jak często wracają.
##Akcja: Obliczenie Liczby Transakcji na klienta i Skumulowanej Wartości Zakupów (Lifetime_Value), grupowanie po customer_key (zgodnie z kodem zaproponowanym w mojej ostatniej odpowiedzi).

### ETAP 6: ANALIZA WARTOŚCI I LOJALNOŚCI KLIENTA 

WITH CustomerMetrics AS (
    -- 1. Rekonstrukcja ID Klienta i Obliczenie Metryk
    SELECT
        CASE
            WHEN t.card IS NOT NULL THEN t.card
            ELSE 'CASH_' || t.cash_type
        END AS card_id,

        t.order_id,
        t.total_value_of_order,
        t.total_products_in_order, -- DODANO: Ilość produktów w pojedynczej transakcji
        t.datetime 
    FROM
        `sales.sales_transactions` t
    WHERE
        t.card IS NOT NULL
),
RecencyDate AS (
    -- 2. Ustalenie daty referencyjnej
    SELECT
        MAX(DATE(datetime)) AS max_date
    FROM
        `sales.sales_transactions`
)
SELECT
    cm.card_id AS card, 
    'CARD' AS customer_type, 
    
    -- R: Recency (Aktualność)
    DATE_DIFF(
        (SELECT max_date FROM RecencyDate),
        MAX(DATE(cm.datetime)),
        DAY
    ) AS R_recency_days_since_last_purchase,
    
    -- F: Frequency (Częstotliwość)
    COUNT(DISTINCT cm.order_id) AS F_total_orders,
    
    -- M: Monetary (Wartość Pieniężna / LTV)
    SUM(cm.total_value_of_order) AS M_lifetime_value,
    
    -- DODANA NOWA METRYKA: Średnia Ilość Produktów w Koszyku Klienta (UPT)
    AVG(cm.total_products_in_order) AS avg_products_per_order_per_customer,
    
    -- Dodatkowa metryka AOV (Średnia Wartość Zamówienia)
    AVG(cm.total_value_of_order) AS avg_order_value_per_customer
    
FROM
    CustomerMetrics cm
GROUP BY
    1, 2 
HAVING
    F_total_orders > 1
ORDER BY
    M_lifetime_value DESC;

--- tabela przedstawia klientów którzy zostawili najwięcej pieniędzy w kawiarni. Dane dają możliwość segmentacji i w zależnosci od strategii kawiarni i możliwości finansowych / technicznych można podjąć celowane działania na utrzymanie (obsługa), optymalizację (upselling), przypomnienie o sobie (sms z przypomnieniem, rabatem, gratisem), odzyskanie (analogicznie z większą zachętą) 
# CRR - client_retention_rate
# CRR MoM
WITH MonthlyCustomers AS (
    -- 1. Identyfikacja unikalnych klientów w każdym miesiącu (Wykluczenie 2025-03)
    SELECT DISTINCT
        FORMAT_DATE('%Y-%m', date) AS period_month,
        card
    FROM
        `sales.sales_transactions`
    WHERE
        card IS NOT NULL 
        -- KLUCZOWA ZMIANA: WYKLUCZENIE NIEPEŁNEGO MIESIĄCA
        AND FORMAT_DATE('%Y-%m', date) < '2025-03' 
),
RetentionData AS (
    -- 2. Ustalenie, czy klient powrócił w następnym miesiącu
    SELECT
        period_month,
        card,
        LAG(period_month, 1) 
            OVER (PARTITION BY card ORDER BY period_month) AS previous_month_active
    FROM
        MonthlyCustomers
),
MonthlyMetrics AS (
    -- 3. Agregacja miar na poziomie miesiąca
    SELECT
        period_month,
        COUNT(card) AS end_period_customers,
        SUM(CASE WHEN previous_month_active IS NOT NULL THEN 1 ELSE 0 END) AS retained_customers
    FROM
        RetentionData
    GROUP BY
        period_month
),
FinalMetrics AS (
    -- 4. Ustalenie bazy klientów na początku okresu (Start)
    SELECT
        m.*,
        LAG(m.end_period_customers) OVER (ORDER BY m.period_month) AS start_period_customers
    FROM
        MonthlyMetrics m
)
SELECT
    period_month,
    end_period_customers,
    start_period_customers,
    retained_customers,
    -- Obliczenie CRR
    ROUND(
        (retained_customers * 100.0) / start_period_customers, 2
    ) AS monthly_retention_rate
FROM
    FinalMetrics
WHERE
    start_period_customers IS NOT NULL
ORDER BY
    period_month;

--- Usunąłem marzec 2025 jako niepełny miesiąc co zaburza analizę
--- 2025-02 jeset anomalią kalendarza - początek miesiąca to sobota, w weekend jest mniej klientów

# CRR QoQ
WITH QuarterlyCustomers AS (
    -- 1. Identyfikacja unikalnych klientów w każdym kwartale
    SELECT DISTINCT
        -- Tworzenie klucza kwartału: ROK-Q[Numer Kwartału] (np. 2024-Q1)
        FORMAT_DATE('%Y-Q', date) || CAST(EXTRACT(QUARTER FROM date) AS STRING) AS period_quarter,
        card
    FROM
        `sales.sales_transactions`
    WHERE
        card IS NOT NULL 
        -- KLUCZOWA ZMIANA: WYKLUCZENIE NIEPEŁNEGO MIESIĄCA/KWARTAŁU
        -- Q1 2025 (Styczeń, Luty, Marzec) jest niepełny, więc wykluczamy cały Q1 2025
        AND FORMAT_DATE('%Y-Q', date) < '2025-Q1'
),
RetentionData AS (
    -- 2. Ustalenie, czy klient powrócił w następnym kwartale
    SELECT
        period_quarter,
        card,
        -- Czas poprzedniego okresu, w którym klient był aktywny.
        LAG(period_quarter, 1) 
            OVER (PARTITION BY card ORDER BY period_quarter) AS previous_quarter_active
    FROM
        QuarterlyCustomers
),
QuarterlyMetrics AS (
    -- 3. Agregacja miar na poziomie kwartału
    SELECT
        period_quarter,
        COUNT(card) AS end_period_customers, -- Klienci na Koniec Okresu (Baza)
        -- Klienci UTRZYMANI: byli aktywni w bieżącym kwartale ORAZ w poprzednim kwartale.
        SUM(CASE WHEN previous_quarter_active IS NOT NULL THEN 1 ELSE 0 END) AS retained_customers
    FROM
        RetentionData
    GROUP BY
        period_quarter
),
FinalMetrics AS (
    -- 4. Ustalenie bazy klientów na początku okresu (Klienci na Start Okresu)
    SELECT
        m.*,
        -- Klienci na koniec Q-1 to baza na start Q. Używamy LAG na end_period_customers.
        LAG(m.end_period_customers) OVER (ORDER BY m.period_quarter) AS start_period_customers
    FROM
        QuarterlyMetrics m
)
SELECT
    period_quarter,
    end_period_customers,
    start_period_customers,
    retained_customers,
    -- Obliczenie CRR: CRR = (Retained Customers / Start Period Customers) * 100
    ROUND(
        (retained_customers * 100.0) / start_period_customers, 2
    ) AS quarterly_retention_rate
FROM
    FinalMetrics
WHERE
    start_period_customers IS NOT NULL -- Pomijamy pierwszy kwartał
ORDER BY
    period_quarter;

--- Q1 2024 został pominięty (baza jest od 03-2024)
--- Q1 2025 jest niepełny ale brakuje 9/90 dni - wynik jest zaburzony ale może stanowić pewną informacje

#Etap 7: Analiza Trendów i Wzrostu Sprzedaży (Growth) 📈
#Cel: Ocena wydajności sprzedaży w czasie.
#Akcja:
#Tempo Wzrostu (Miesięczne/Kwartalne): Porównanie Total_Revenue i Total_Orders z poprzednimi okresami (wykorzystanie funkcji LAG na danych zagregowanych miesięcznie).
#Analiza Sezonowości: Total_Revenue wg Dnia Tygodnia / Miesiąca.

# Wzrost sprzedaży MoM
WITH MonthlySummary AS (
    -- Agregacja danych do poziomu miesięcznego
    SELECT
        FORMAT_DATE('%Y-%m', DATE(t.datetime)) AS sales_month,
        COUNT(DISTINCT t.order_id) AS monthly_orders,
        SUM(t.money) AS monthly_revenue
    FROM
        `sales.sales_transactions` t
    GROUP BY 1
    ORDER BY 1
)
SELECT
    s.sales_month,
    s.monthly_orders,
    s.monthly_revenue,
    
    -- Wzrost Liczby Zamówień MoM
    ROUND(
        (s.monthly_orders - LAG(s.monthly_orders, 1) OVER (ORDER BY s.sales_month)) 
        / LAG(s.monthly_orders, 1) OVER (ORDER BY s.sales_month),
        4
    ) AS orders_growth_mom,
        
    -- Wzrost Przychodu MoM
    ROUND(
        (s.monthly_revenue - LAG(s.monthly_revenue, 1) OVER (ORDER BY s.sales_month)) 
        / LAG(s.monthly_revenue, 1) OVER (ORDER BY s.sales_month),
        4
    ) AS revenue_growth_mom
FROM
    MonthlySummary s
ORDER BY
    s.sales_month;

--- pokazuje trendy do analizy zmiennosci wg miesięcy

# Wzrost sprzedaży QoQ
WITH QuarterlySummary AS (
    -- 1. Agregacja danych do poziomu kwartalnego
    SELECT
        -- Zmiana grupowania na ROK-Q[Numer Kwartału] (np. 2024-Q2)
        FORMAT_DATE('%Y-Q', DATE(t.datetime)) || CAST(EXTRACT(QUARTER FROM DATE(t.datetime)) AS STRING) AS sales_quarter,
        
        COUNT(DISTINCT t.order_id) AS quarterly_orders,
        SUM(t.total_value_of_order) AS quarterly_revenue
    FROM
        `sales.sales_transactions` t
    -- Filtrowanie dat: Wykluczamy niepełny Q1 2025 (Marzec 2025)
    WHERE
        FORMAT_DATE('%Y-%m', DATE(t.datetime)) < '2025-03'
    GROUP BY 1
    ORDER BY 1
),
QoQCalculations AS (
    -- 2. Obliczenia bazowe (LAG)
    SELECT
        s.sales_quarter,
        s.quarterly_orders,
        s.quarterly_revenue,
        
        -- Bazowe wartości z poprzedniego kwartału (Mianownik dla Wzrostu)
        LAG(s.quarterly_orders, 1) OVER (ORDER BY s.sales_quarter) AS previous_orders,
        LAG(s.quarterly_revenue, 1) OVER (ORDER BY s.sales_quarter) AS previous_revenue
    FROM
        QuarterlySummary s
)
SELECT
    q.sales_quarter,
    q.quarterly_orders,
    q.quarterly_revenue,
    
    -- Wzrost Liczby Zamówień QoQ
    ROUND(
        (q.quarterly_orders - q.previous_orders) / q.previous_orders,
        4
    ) AS orders_growth_qoq,
        
    -- Wzrost Przychodu QoQ
    ROUND(
        (q.quarterly_revenue - q.previous_revenue) / q.previous_revenue,
        4
    ) AS revenue_growth_qoq
FROM
    QoQCalculations q
-- Filtrujemy, aby usunąć pierwszy kwartał bez danych bazowych
WHERE
    q.previous_orders IS NOT NULL 
ORDER BY
    q.sales_quarter;

# ANALIZA SEZONOWOŚCI WG DNIA TYGODNIA
--- cortowanie wg Weekdaysort (rozkład w tygodniu)
SELECT
    t.Weekday,
    SUM(t.money) AS total_revenue,
    COUNT(DISTINCT t.order_id) AS total_orders,
    AVG(t.total_value_of_order) AS avg_order_value
FROM
    `sales.sales_transactions` t
GROUP BY
    1, t.Weekdaysort
ORDER BY
    t.Weekdaysort;

--- sortowanie wg total_orders (Największy Ruch)
SELECT
    t.Weekday, 
    
    SUM(t.money) AS total_revenue,
    COUNT(DISTINCT t.order_id) AS total_orders,
    AVG(t.total_value_of_order) AS avg_order_value
FROM
    `sales.sales_transactions` t
GROUP BY
    1, t.WeekdaySort
ORDER BY
    total_orders DESC;

---Sortowanie wg total_revenue (Najbardziej Dochodowy)
SELECT
    t.Weekday, 
    
    SUM(t.money) AS total_revenue,
    COUNT(DISTINCT t.order_id) AS total_orders,
    AVG(t.total_value_of_order) AS avg_order_value
FROM
    `sales.sales_transactions` t
GROUP BY
    1, t.WeekdaySort
ORDER BY
    total_revenue DESC;

--- ilość transakcji i przychód jest największy pn-pt, sporo mniejszy w sb - nd, jednak średnia wartość zamówienia jest istotnie większa w sb-nd. Warto to uwzględnić w grafiku personelu (ilość osób danego dnia, większe zapotrzebowanie w środku tygodnia, szczególnie poniedziałek). Akcje promocyjne też można dostosować do dnia tygodnia (klientów w sb-nd jest mniej ale są skłonni wydać więcej)

# sezonowość wg dnia tygodnia i godziny
SELECT
    -- Nazwa dnia tygodnia (dla czytelności)
    t.Weekday, 
    
    -- ID dnia tygodnia (do sortowania, zakładając, że istnieje)
    t.WeekdaySort, 
    
    -- Wyodrębnienie godziny (0-23)
    CAST(EXTRACT(HOUR FROM t.datetime) AS INT64) AS hour_of_day,
    
    -- Metryki zagregowane
    SUM(t.money) AS total_revenue,
    COUNT(DISTINCT t.order_id) AS total_orders,
    AVG(t.total_value_of_order) AS avg_order_value
FROM
    `sales.sales_transactions` t
GROUP BY
    1, 2, 3
ORDER BY
    -- Sortowanie logiczne: najpierw dzień (Pon-Niedz), potem godzina (od 0 do 23)
    t.WeekdaySort,
    hour_of_day;
 
 --- daje szczegółowy rozkład godzinowy w dniach tygodnia - przydatne do ustawiania godzin pracy obsady

# filtrowanie konkretnego dnia tygodnia - tutaj poniedziałek jako dzień z największym ruchem
SELECT
    CAST(EXTRACT(HOUR FROM t.datetime) AS INT64) AS hour_of_day,
    SUM(t.money) AS total_revenue,
    COUNT(DISTINCT t.order_id) AS total_orders,
    AVG(t.total_value_of_order) AS avg_order_value
FROM
    `sales.sales_transactions` t
WHERE
    t.Weekday = 'pon.' 
GROUP BY
    1
ORDER BY
    hour_of_day;

# sezonowość wg pory dnia -- KWERENDA: ANALIZA SPRZEDAŻY WEDŁUG PORY DNIA
SELECT
    t.Time_of_Day, -- Użycie istniejącej kolumny kategoryzującej porę dnia
    
    SUM(t.money) AS total_revenue,
    COUNT(DISTINCT t.order_id) AS total_orders,
    AVG(t.total_value_of_order) AS avg_order_value
FROM
    `sales.sales_transactions` t
GROUP BY
    1
ORDER BY
    t.Time_of_Day; -- ZMIANA: Sortowanie bezpośrednio po kolumnie Time_of_Day

--- rozkład wg pory dnia


# Wtap 8. Analiza wariancji

# Analiza Wariancji Transakcji (Odchylenie od Średniej Dziennej AOV)
SELECT
    t.order_id,
    DATE(t.datetime) AS order_date,
    t.total_value_of_order,
    
    -- Obliczenie średniej wartości zamówienia dla całego zbioru (Overall AOV)
    ROUND(AVG(t.total_value_of_order) OVER (), 2) AS avg_overall_aov,
    
    -- Średnia wartość zamówienia z danego dnia (Daily AOV)
    -- Użycie PARTITION BY DATE(t.datetime) gwarantuje, że obliczamy średnią tylko dla transakcji z tego samego dnia
    ROUND(AVG(t.total_value_of_order) OVER (PARTITION BY DATE(t.datetime)), 2) AS avg_daily_aov,
    
    -- Różnica Procentowa od Średniej Dziennej
    -- Wzór: ((Wartość Transakcji - Średnia Dzienna) / Średnia Dzienna) * 100
    ROUND(
        (t.total_value_of_order - AVG(t.total_value_of_order) OVER (PARTITION BY DATE(t.datetime))) 
        / AVG(t.total_value_of_order) OVER (PARTITION BY DATE(t.datetime)) * 100, 
        2
    ) AS daily_aov_variance_percent

FROM
    `sales.sales_transactions` t
ORDER BY
    daily_aov_variance_percent DESC -- Sortowanie pozwala zobaczyć największe anomalie (wyjątkowo duże zamówienia)
LIMIT 100;
