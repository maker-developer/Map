# Enriched place data

The public downloads are in the `places/v1/` prefix of the Map R2 bucket:

- [manifest.json](https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/places/v1/manifest.json)
- [Overture SQLite, gzip compressed](https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/places/v1/overture.sqlite.gz)
- [OpenStreetMap SQLite, gzip compressed](https://pub-031a310ad68042d59e4273a0b01a7dc1.r2.dev/places/v1/openstreetmap.sqlite.gz)

Both databases cover Miami-Dade, Broward and Monroe. Download a `.gz` file, decompress it, then open the resulting SQLite database. Each database has the same `lugares` table and `lugares_fts` full-text index. Optional fields stay `NULL` when the source does not provide them. Query each provider database independently and merge search results in the application; this preserves their different license obligations.

Key fields include `name`, `brand`, `kind`, `category`, `description`, coordinates, address, phone, email, website, social links, opening hours, payment/services JSON, operating status, confidence, source/license/attribution and photos JSON. Overture stores per-record source and license information in `details_json.sources`. OSM records require visible attribution to OpenStreetMap and carry ODbL-1.0. Commons photo references include their own author, credit and license metadata; image files are not mirrored.

The Miami-Dade LocalBusinessTax/Business Tracker layer is excluded. Its official metadata classifies access as restricted for internal use and says the telephone information is not for public access. The generator does not fetch or retain those records. See [`data/SOURCES.md`](../../../data/SOURCES.md).

Regenerate with:

```sh
python3 -m pip install -r data/requirements.txt
python3 data/scripts/lugares_enriquecidos.py
```

The OSM extract uses `osmium-tool`; install it separately. Generated `.sqlite` and `.gz` files are ignored by Git; `manifest.json` records the public object names, sizes, coverage, licenses and available-field counts.
