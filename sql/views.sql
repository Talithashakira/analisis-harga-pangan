-- =====================================================================
-- Serving layer untuk Power BI
-- Aturan: view yang masih akan diagregasi lagi (oleh view lain atau
-- oleh Power BI) TIDAK dibulatkan. Pembulatan hanya di hasil akhir.
-- =====================================================================

DROP VIEW IF EXISTS
    dim_komoditas,
    dim_provinsi,
    dim_tahun,
    v_matriks_risiko,
    v_efek_lebaran,
    v_kenaikan_lebaran,
    v_volatilitas,
    v_harga_bulanan,
    v_indeks_provinsi,
    v_sourcing_jawa,
    v_tren_tahunan
CASCADE;


-- ---------------------------------------------------------------------
-- 1. Harga rata-rata nasional per bulan (untuk grafik tren)
-- ---------------------------------------------------------------------
CREATE VIEW v_harga_bulanan AS
SELECT
    komoditas,
    DATE_TRUNC('month', tanggal)::date AS bulan,
    AVG(harga)                          AS harga_rata
FROM harga_pangan
WHERE tanggal < '2026-02-01'            -- Feb 2026 belum lengkap
GROUP BY komoditas, DATE_TRUNC('month', tanggal);


-- ---------------------------------------------------------------------
-- 2. Volatilitas per komoditas (Q1)
-- ---------------------------------------------------------------------
CREATE VIEW v_volatilitas AS
WITH perubahan AS (
    SELECT
        komoditas,
        (harga_rata / LAG(harga_rata) OVER (PARTITION BY komoditas ORDER BY bulan) - 1) * 100
            AS pct_mom
    FROM v_harga_bulanan
)
SELECT
    komoditas,
    ROUND(AVG(ABS(pct_mom))::numeric, 1) AS rata_gejolak_bulanan_pct,
    ROUND(MAX(pct_mom)::numeric, 1)      AS lonjakan_terbesar_pct,
    ROUND(MIN(pct_mom)::numeric, 1)      AS penurunan_terbesar_pct
FROM perubahan
GROUP BY komoditas;


-- ---------------------------------------------------------------------
-- 3. Kenaikan menjelang Lebaran per komoditas per tahun (Q2)
--    TIDAK dibulatkan, karena dipakai lagi oleh v_efek_lebaran
-- ---------------------------------------------------------------------
CREATE VIEW v_kenaikan_lebaran AS
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
)
SELECT
    komoditas,
    tahun,
    (harga_pra_lebaran / harga_baseline - 1) * 100 AS kenaikan_pct
FROM periode;


-- ---------------------------------------------------------------------
-- 4. Ringkasan efek Lebaran (Q2b) — pembulatan di langkah terakhir
-- ---------------------------------------------------------------------
CREATE VIEW v_efek_lebaran AS
SELECT
    komoditas,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY kenaikan_pct))::numeric, 1) AS median_pct,
    COUNT(*) FILTER (WHERE kenaikan_pct > 0)                                      AS tahun_naik
FROM v_kenaikan_lebaran
GROUP BY komoditas;


-- ---------------------------------------------------------------------
-- 5. Indeks harga provinsi vs nasional, per komoditas, 2025 (Q3)
--    TIDAK dibulatkan, karena Power BI akan merata-ratakannya lagi
-- ---------------------------------------------------------------------
CREATE VIEW v_indeks_provinsi AS
WITH nasional_harian AS (
    SELECT komoditas, tanggal, AVG(harga) AS harga_nasional
    FROM harga_pangan
    WHERE tanggal < '2026-01-01'
    GROUP BY komoditas, tanggal
)
SELECT
    h.provinsi,
    h.komoditas,
    EXTRACT(YEAR FROM h.tanggal)::int      AS tahun,
    AVG(h.harga / n.harga_nasional * 100)  AS indeks
FROM harga_pangan h
JOIN nasional_harian n USING (komoditas, tanggal)
GROUP BY h.provinsi, h.komoditas, EXTRACT(YEAR FROM h.tanggal);


-- ---------------------------------------------------------------------
-- 6. Sourcing di Jawa: harga 2025 dan selisih vs Jakarta (Q3b)
-- ---------------------------------------------------------------------
CREATE VIEW v_sourcing_jawa AS
WITH jawa AS (
    SELECT
        komoditas,
        provinsi,
        EXTRACT(YEAR FROM tanggal)::int AS tahun,
        AVG(harga)                      AS harga_rata
    FROM harga_pangan
    WHERE tanggal < '2026-01-01'
      AND provinsi IN ('DKI Jakarta', 'Banten', 'Jawa Barat',
                       'Jawa Tengah', 'DI Yogyakarta', 'Jawa Timur')
    GROUP BY komoditas, provinsi, EXTRACT(YEAR FROM tanggal)
),
dengan_jakarta AS (
    SELECT
        *,
        MAX(harga_rata) FILTER (WHERE provinsi = 'DKI Jakarta')
            OVER (PARTITION BY komoditas, tahun) AS harga_jakarta
    FROM jawa
)
SELECT
    komoditas,
    provinsi,
    tahun,
    harga_rata,
    (harga_rata / harga_jakarta - 1) * 100 AS selisih_vs_jakarta_pct
FROM dengan_jakarta;


-- ---------------------------------------------------------------------
-- 7. Tren tahunan dan kenaikan kumulatif sejak 2022 (Q4)
-- ---------------------------------------------------------------------
CREATE VIEW v_tren_tahunan AS
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
WINDOW w AS (PARTITION BY komoditas ORDER BY tahun);

-- ---------------------------------------------------------------------
-- 8. Matriks risiko: satu baris per komoditas (visual utama dashboard)
-- ---------------------------------------------------------------------
CREATE VIEW v_matriks_risiko AS
SELECT
    v.komoditas,
    v.rata_gejolak_bulanan_pct,
    t.vs_2022_pct   AS kenaikan_2022_2025_pct,
    e.median_pct    AS efek_lebaran_median_pct,
    e.tahun_naik    AS lebaran_tahun_naik,
    CASE
        WHEN t.vs_2022_pct >= 15             THEN 'Trend risk'
        WHEN v.rata_gejolak_bulanan_pct >= 5 THEN 'Volatility risk'
        ELSE 'Low risk'
    END AS kelompok_risiko
FROM v_volatilitas v
JOIN v_tren_tahunan t ON t.komoditas = v.komoditas AND t.tahun = 2025
JOIN v_efek_lebaran e ON e.komoditas = v.komoditas;

-- ---------------------------------------------------------------------
-- 9. Dimensi komoditas: label rapi + kelompok risiko
-- ---------------------------------------------------------------------
CREATE VIEW dim_komoditas AS
SELECT
    komoditas,
    INITCAP(REPLACE(komoditas, '_', ' ')) AS nama_komoditas,   -- cabai_rawit -> Cabai Rawit
    kelompok_risiko
FROM v_matriks_risiko;


-- ---------------------------------------------------------------------
-- 10. Dimensi provinsi: kelompok pulau + label untuk peta
-- ---------------------------------------------------------------------
CREATE VIEW dim_provinsi AS
SELECT
    provinsi,
    CASE
        WHEN provinsi IN ('DKI Jakarta', 'Banten', 'Jawa Barat',
                          'Jawa Tengah', 'DI Yogyakarta', 'Jawa Timur')    THEN 'Jawa'
        WHEN provinsi IN ('Bali', 'Nusa Tenggara Barat', 'Nusa Tenggara Timur') THEN 'Bali & Nusa Tenggara'
        WHEN provinsi LIKE 'Kalimantan%'                                    THEN 'Kalimantan'
        WHEN provinsi LIKE 'Sulawesi%' OR provinsi = 'Gorontalo'            THEN 'Sulawesi'
        WHEN provinsi IN ('Maluku', 'Maluku Utara', 'Papua', 'Papua Barat') THEN 'Maluku & Papua'
        ELSE 'Sumatera'
    END                          AS pulau,
    provinsi || ', Indonesia'    AS lokasi_peta
FROM (SELECT DISTINCT provinsi FROM harga_pangan) p;


-- ---------------------------------------------------------------------
-- 11. Dimensi tahun (tahun lengkap saja)
-- ---------------------------------------------------------------------
CREATE VIEW dim_tahun AS
SELECT generate_series(2022, 2025) AS tahun;