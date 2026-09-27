-- Q3: Indeks harga provinsi relatif terhadap rata-rata nasional (2025, tahun penuh terakhir)
-- Indeks 100 = sama dengan rata-rata nasional; 120 = 20% lebih mahal
WITH nasional_harian AS (
    SELECT komoditas, tanggal, AVG(harga) AS harga_nasional
    FROM harga_pangan
    WHERE tanggal BETWEEN '2025-01-01' AND '2025-12-31'
    GROUP BY komoditas, tanggal
),
relatif AS (
    SELECT
        h.provinsi,
        h.komoditas,
        AVG(h.harga / n.harga_nasional * 100) AS indeks
    FROM harga_pangan h
    JOIN nasional_harian n USING (komoditas, tanggal)
    GROUP BY h.provinsi, h.komoditas
)
SELECT
    provinsi,
    ROUND(AVG(indeks)::numeric, 1)          AS indeks_rata,
    RANK() OVER (ORDER BY AVG(indeks) DESC) AS peringkat_termahal
FROM relatif
GROUP BY provinsi
ORDER BY indeks_rata DESC;