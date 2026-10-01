# Indonesian Food Price Risk Analysis

**Which ingredients carry the most price risk for a restaurant chain in Java, when does that risk appear, and where can they be sourced more cheaply?**

An end-to-end analysis of 481,236 daily retail prices (10 strategic food commodities × 34 provinces, Jan 2022 to Feb 2026) from Bank Indonesia's PIHPS. The data is reshaped in Python, analysed in PostgreSQL, served as a star schema of SQL views, and presented in a two-page Power BI dashboard with a one-page recommendation memo.

![Page 1: Price risk](dashboard/page1.png)
![Page 2: Where to source](dashboard/page2.png)

📓 [Analysis notebook](notebooks/analisis_harga_pangan.ipynb)

---

## Key findings

| # | Finding | Evidence |
|---|---|---|
| 1 | **Two different kinds of price risk.** Some ingredients creep up steadily, others swing sharply. | Garlic **+42.1%**, rice **+30.5%**, sugar **+26.2%** (2022 to 2025) while moving only 0.9 to 3.1% a month. Chilies and shallots swing **11 to 14% a month**. |
| 2 | **Chili spikes are large and not seasonal to Lebaran.** | Cabai rawit jumped **58.2%** in one month (Dec 2025). It rose before Lebaran in only 2 of 4 years. |
| 3 | **Garlic is the one reliable Lebaran effect.** | Rose in the 4 weeks before Lebaran in **4 of 4 years**, median **+6.9%**. |
| 4 | **East Java is the cheapest source in Java.** | Cheapest Java province for 8 of 10 commodities in 2025. vs Jakarta: cabai rawit **-36.7%**, cabai merah **-33.0%**, garlic **-31.5%**. |

## Recommendations

| Group | Risk | Action |
|---|---|---|
| Garlic, rice, sugar | Trend | **Lock in prices**: annual contracts; buy garlic 1 to 2 months before Lebaran. |
| Chilies, shallots | Volatility | **Stay flexible, don't stockpile**: backup suppliers, flexible menu pricing, weekly price checks. |
| Chilies, garlic | Location | **Pilot East Java sourcing** for one quarter and compare landed cost with Jakarta. |
| Proteins, eggs, cooking oil | Low | No change: keep local suppliers. |

---

## Architecture

```mermaid
flowchart LR
    A[Kaggle CSV<br/>10 files, wide format] -->|pandas melt<br/>+ quality checks| B[(PostgreSQL<br/>harga_pangan<br/>481K rows)]
    B -->|sql/01 to 04| C[Analysis queries<br/>Q1 to Q4]
    B -->|sql/views.sql| D[Serving layer<br/>3 dims + 8 views]
    D -->|published| E[(Neon<br/>cloud Postgres)]
    E -->|Import mode| F[Power BI<br/>2 pages, 22 measures]
```

| Layer | Tool | Why |
|---|---|---|
| Ingestion and reshaping | Python, pandas | The source ships one wide CSV per commodity (provinces as columns). `melt` turns it into one long table so every dimension is a column value SQL can group by. |
| Storage and analysis | PostgreSQL 15 in Docker | All analysis is written in SQL, one question per file. A primary key on `(tanggal, provinsi, komoditas)` enforces the grain. |
| Serving layer | SQL views | A small star schema (`dim_komoditas`, `dim_provinsi`, `dim_tahun` + fact views). Power BI never touches the raw table. |
| Cloud | Neon (Postgres) | Power BI runs on Windows while the database runs in Docker on Linux, so the views are also published to Neon. Credentials live in a git-ignored `.env`. |
| Presentation | Power BI | Two pages, single-direction relationships from dimensions to facts, DAX measures for KPIs and conditional colours. |

## SQL techniques

| Question | File | Techniques |
|---|---|---|
| Which commodities are most volatile? | `sql/01_volatilitas.sql` | CTEs, `DATE_TRUNC`, `LAG() OVER (PARTITION BY ...)` |
| When did the biggest spikes happen? | `sql/01b_lonjakan_terbesar.sql` | `RANK()`, filtering a window result through a CTE, `NULLS LAST` |
| How much do prices rise before Lebaran? | `sql/02_efek_lebaran.sql` | `VALUES` as an inline table, `CROSS JOIN`, `AVG(...) FILTER (WHERE ...)` |
| Which Lebaran effects are reliable? | `sql/02b_efek_lebaran_ringkas.sql` | `PERCENTILE_CONT(0.5) WITHIN GROUP` (median), `COUNT(*) FILTER` |
| Which provinces are most expensive? | `sql/03_disparitas_provinsi.sql` | Price index vs national daily average, window function over `GROUP BY` |
| Within Java, where is each commodity cheapest? | `sql/03b_sourcing_jawa.sql` | `MAX(...) FILTER (WHERE ...) OVER (PARTITION BY ...)` instead of a self-join |
| Long-term trend | `sql/04_tren_tahunan.sql` | `LAG`, `FIRST_VALUE`, named `WINDOW` clause |
| Dashboard serving layer | `sql/views.sql` | Star schema views, re-runnable `DROP ... CASCADE`, rounding only at the last step |

## Data quality

| Check | Result | How it was handled |
|---|---|---|
| Duplicates at grain | 0 | Enforced as a primary key in PostgreSQL |
| Zero, negative or null prices | 0 | |
| Missing calendar days | **87 of 1,504 (5.8%)**, mostly sporadic weekends plus 2022 national holidays | Volatility and trends are computed on **monthly and yearly** averages, so `LAG()` never compares days that are not adjacent |
| Uneven date coverage | Cabai merah and cabai rawit have 2 extra dates (1,417 vs 1,415) | Negligible after monthly aggregation |
| Imputation | The source was pre-imputed by the uploader (method unknown) | Stated as a limitation: true volatility may be higher |

Lebaran windows from 2023 onwards contain no missing days, so the Lebaran analysis is not affected by the gaps.

## Limitations

- Prices are **retail traditional-market** prices, not wholesale contract prices.
- **Logistics and spoilage costs are not included**, so the East Java price gap is an opportunity to test, not a guaranteed saving.
- National and regional averages are **unweighted**: each province counts equally.
- The data uses the **34 pre-2022 provinces** (Papua is not split).
- Weather and harvest explanations for chili spikes are hypotheses; the dataset has no weather data.

---

## How to run

**Requirements:** Python 3.12, Docker, Power BI Desktop (Windows) for the dashboard.

```bash
# 1. Clone and set up Python
git clone https://github.com/USERNAME/analisis-harga-pangan.git
cd analisis-harga-pangan
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 2. Start PostgreSQL (port 5434)
docker compose up -d
```

3. Download the [PIHPS dataset from Kaggle](https://www.kaggle.com/datasets/muhyusuf1112/indonesia-commodity-price-based-piphs-source) and place the `pasar_tradisional/Cleaned_After_Imputation/` CSV files in `data/pasar_tradisional/Cleaned_After_Imputation/`.
4. *(Optional, for Power BI)* Create a `.env` file in the project root with a Neon connection string:
   ```text
   NEON_URL=postgresql+psycopg2://USER:PASSWORD@HOST/harga_pangan?sslmode=require
   ```
5. Run `notebooks/analisis_harga_pangan.ipynb` top to bottom. Without `.env`, everything runs against the local database only.
6. Open `dashboard/harga_pangan.pbix` and update the data source credentials to your own Neon database.

## Project structure

```text
analisis-harga-pangan/
├── dashboard/
│   ├── harga_pangan.pbix          # Power BI report
│   ├── harga_pangan.pdf           # exported report
│   ├── harga_pangan_theme.json    # colour theme
│   ├── page1.png
│   └── page2.png
├── data/                          # raw CSVs (git-ignored, download from Kaggle)
├── docs/
│   ├── memo.md                    # one-page recommendation memo
│   └── memo.pdf
├── notebooks/
│   └── analisis_harga_pangan.ipynb
├── sql/
│   ├── 01_volatilitas.sql
│   ├── 01b_lonjakan_terbesar.sql
│   ├── 02_efek_lebaran.sql
│   ├── 02b_efek_lebaran_ringkas.sql
│   ├── 03_disparitas_provinsi.sql
│   ├── 03b_sourcing_jawa.sql
│   ├── 04_tren_tahunan.sql
│   └── views.sql                  # star-schema serving layer for Power BI
├── docker-compose.yml
├── requirements.txt
└── .gitignore                     # data/, .venv/, .env
```

## Data source

Bank Indonesia, *Pusat Informasi Harga Pangan Strategis* (PIHPS), daily prices in traditional markets, via the Kaggle dataset [Indonesia Commodity Price based on PIHPS](https://www.kaggle.com/datasets/muhyusuf1112/indonesia-commodity-price-based-piphs-source). Official source: [bi.go.id/hargapangan](https://www.bi.go.id/hargapangan).
