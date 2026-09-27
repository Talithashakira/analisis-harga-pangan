-- Q3b: Harga rata-rata 2025 per komoditas di provinsi Jawa, dan selisihnya vs DKI Jakarta
WITH jawa AS (
    SELECT komoditas, provinsi, AVG(harga) AS harga_rata
    FROM harga_pangan
    WHERE tanggal BETWEEN '2025-01-01' AND '2025-12-31'
      AND provinsi IN ('DKI Jakarta', 'Banten', 'Jawa Barat',
                       'Jawa Tengah', 'DI Yogyakarta', 'Jawa Timur')
    GROUP BY komoditas, provinsi
),
dengan_jakarta AS (
    SELECT
        *,
        MAX(harga_rata) FILTER (WHERE provinsi = 'DKI Jakarta')
            OVER (PARTITION BY komoditas) AS harga_jakarta
    FROM jawa
)
SELECT
    komoditas,
    provinsi,
    ROUND(harga_rata::numeric, 0)                                AS harga_rata,
    RANK() OVER (PARTITION BY komoditas ORDER BY harga_rata)     AS peringkat_termurah,
    ROUND(((harga_rata / harga_jakarta - 1) * 100)::numeric, 1)  AS selisih_vs_jakarta_pct
FROM dengan_jakarta
ORDER BY komoditas, peringkat_termurah;