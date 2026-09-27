-- Q2b: Ringkasan efek Lebaran per komoditas
-- median_pct : tahan terhadap satu tahun ekstrem (mis. minyak goreng 2022)
-- tahun_naik : dari 4 tahun, berapa kali harga naik menjelang Lebaran

WITH lebaran(tahun, tgl) AS (
    VALUES (2022, DATE '2022-05-02'),
           (2023, DATE '2023-04-22'),
           (2024, DATE '2024-04-10'),
           (2025, DATE '2025-03-31')
),

nasional AS (
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
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY kenaikan_pct))::numeric, 1) AS median_pct,
    COUNT(*) FILTER (WHERE kenaikan_pct > 0)                                      AS tahun_naik,
    ROUND(MIN(kenaikan_pct)::numeric, 1)                                          AS terendah_pct,
    ROUND(MAX(kenaikan_pct)::numeric, 1)                                          AS tertinggi_pct
FROM kenaikan
GROUP BY komoditas
ORDER BY tahun_naik DESC, median_pct DESC;