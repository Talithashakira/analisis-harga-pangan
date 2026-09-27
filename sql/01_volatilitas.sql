-- Q1: Komoditas mana yang harganya paling bergejolak?
-- Grain input : tanggal × provinsi × komoditas
-- Pendekatan  : agregasi ke rata-rata nasional bulanan dulu (menghindari masalah tanggal bolong),
--               lalu ukur perubahan bulan-ke-bulan dengan LAG.

WITH bulanan AS (
    SELECT
        komoditas,
        DATE_TRUNC('month', tanggal)::date AS bulan,
        AVG(harga)                          AS harga_rata
    FROM harga_pangan
    WHERE tanggal < '2026-02-01'            -- Feb 2026 baru 12 hari, bulan tidak lengkap
    GROUP BY komoditas, DATE_TRUNC('month', tanggal)
),

perubahan AS (
    SELECT
        komoditas,
        bulan,
        harga_rata,
        (harga_rata / LAG(harga_rata) OVER (PARTITION BY komoditas ORDER BY bulan) - 1) * 100
            AS pct_mom
    FROM bulanan
)

SELECT
    komoditas,
    ROUND(AVG(ABS(pct_mom))::numeric, 1)                   AS rata_gejolak_bulanan_pct,
    ROUND(MAX(pct_mom)::numeric, 1)                        AS lonjakan_terbesar_pct,
    ROUND(MIN(pct_mom)::numeric, 1)                        AS penurunan_terbesar_pct,
    ROUND((STDDEV(harga_rata) / AVG(harga_rata) * 100)::numeric, 1) AS cv_pct
FROM perubahan
GROUP BY komoditas
ORDER BY rata_gejolak_bulanan_pct DESC;