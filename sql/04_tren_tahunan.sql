-- Q4: Harga rata-rata nasional per tahun, kenaikan YoY, dan kenaikan kumulatif sejak 2022
WITH tahunan AS (
    SELECT
        komoditas,
        EXTRACT(YEAR FROM tanggal)::int AS tahun,
        AVG(harga)                      AS harga_rata
    FROM harga_pangan
    WHERE tanggal < '2026-01-01'        -- 2026 belum lengkap
    GROUP BY komoditas, EXTRACT(YEAR FROM tanggal)
)
SELECT
    komoditas,
    tahun,
    ROUND(harga_rata::numeric, 0) AS harga_rata,
    ROUND(((harga_rata / LAG(harga_rata) OVER w - 1) * 100)::numeric, 1)         AS yoy_pct,
    ROUND(((harga_rata / FIRST_VALUE(harga_rata) OVER w - 1) * 100)::numeric, 1) AS vs_2022_pct
FROM tahunan
WINDOW w AS (PARTITION BY komoditas ORDER BY tahun)
ORDER BY komoditas, tahun;