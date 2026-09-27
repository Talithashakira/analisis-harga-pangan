-- Q2: Kenaikan harga menjelang Lebaran vs periode normal, per komoditas per tahun
-- Baseline      : H-90 s.d. H-61 (sebelum Ramadan)
-- Pra-Lebaran   : H-28 s.d. H-1

WITH lebaran(tahun, tgl) AS (
    VALUES (2022, DATE '2022-05-02'),
           (2023, DATE '2023-04-22'),
           (2024, DATE '2024-04-10'),
           (2025, DATE '2025-03-31')
),

nasional AS (   -- rata-rata nasional harian
    SELECT komoditas, tanggal, AVG(harga) AS harga
    FROM harga_pangan
    GROUP BY komoditas, tanggal
),

periode AS (
    SELECT
        n.komoditas,
        l.tahun,
        AVG(n.harga) FILTER (WHERE n.tanggal BETWEEN l.tgl - 90 AND l.tgl - 61) AS harga_baseline,
        AVG(n.harga) FILTER (WHERE n.tanggal BETWEEN l.tgl - 28 AND l.tgl - 1)  AS harga_pra_lebaran
    FROM nasional n
    CROSS JOIN lebaran l
    WHERE n.tanggal BETWEEN l.tgl - 90 AND l.tgl - 1
    GROUP BY n.komoditas, l.tahun
),

kenaikan AS (
    SELECT
        komoditas,
        tahun,
        (harga_pra_lebaran / harga_baseline - 1) * 100 AS kenaikan_pct
    FROM periode
)

SELECT
    komoditas,
    tahun,
    ROUND(kenaikan_pct::numeric, 1)                                    AS kenaikan_pct,
    ROUND(AVG(kenaikan_pct) OVER (PARTITION BY komoditas)::numeric, 1) AS rata_4_tahun_pct
FROM kenaikan
ORDER BY rata_4_tahun_pct DESC, komoditas, tahun;