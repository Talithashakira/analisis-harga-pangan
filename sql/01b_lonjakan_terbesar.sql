-- Q1b: 2 lonjakan bulanan terbesar per komoditas, dan kapan terjadinya
WITH bulanan AS (
    SELECT komoditas, DATE_TRUNC('month', tanggal)::date AS bulan, AVG(harga) AS harga_rata
    FROM harga_pangan
    WHERE tanggal < '2026-02-01'
    GROUP BY komoditas, DATE_TRUNC('month', tanggal)
),
perubahan AS (
    SELECT komoditas, bulan,
           (harga_rata / LAG(harga_rata) OVER (PARTITION BY komoditas ORDER BY bulan) - 1) * 100 AS pct_mom
    FROM bulanan
),
ranking AS (
    SELECT *, RANK() OVER (PARTITION BY komoditas ORDER BY pct_mom DESC NULLS LAST) AS urutan
    FROM perubahan
)
SELECT komoditas, bulan, ROUND(pct_mom::numeric, 1) AS pct_mom
FROM ranking
WHERE urutan <= 2
ORDER BY komoditas, urutan;