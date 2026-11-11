# Dashboard de retail: layout de dos páginas

Lienzo **16:9, 1280 × 720 px** en las dos páginas (*Diseño > Tamaño de la página > Personalizado*). Posiciones en *Formato > General > Propiedades* (X, Y, ancho, alto).

## Orden de armado
1. **Obtener datos > Base de datos MySQL**, servidor `localhost`, base `retail_db`. Marcá **las cinco vistas**: `vw_fact_ventas`, `vw_fact_inventario`, `vw_dim_producto`, `vw_dim_sucursal` y `vw_dim_cliente`, y tocá *Transformar datos*. Requiere MySQL Connector/NET 8.0.x de 64 bits.
2. **Renombrar las tablas** (clic derecho > Cambiar nombre): `fact_ventas`, `fact_inventario`, `dim_producto`, `dim_sucursal`, `dim_cliente`. Tipo de `fecha`: **Fecha**.
3. Pegar la tabla `Calendario` de `medidas.dax`, **marcarla como tabla de fechas** y ordenar `Día semana` por `Día semana N`.
4. **Crear las 6 relaciones** en la Vista de modelo (están listadas en `medidas.dax`), todas uno a varios con filtro en una sola dirección. Fijate que `dim_cliente[cliente_id] → fact_ventas[cliente_id]` quede como uno a varios aunque haya ventas sin cliente.
5. Pegar las medidas de `medidas.dax`.
6. *Diseño > Importar tema* > `tema_retail.json`.
7. Colocar las visuales según las tablas.

## Página 1: Ventas

| Fila | Visual | Campos | X | Y | Ancho | Alto |
|---|---|---|---|---|---|---|
| Filtros | Segmentación (lista desplegable) | `Calendario[Año]` | 20 | 10 | 300 | 50 |
| Filtros | Segmentación (lista desplegable) | `dim_sucursal[region]` | 340 | 10 | 300 | 50 |
| Filtros | Segmentación (lista desplegable) | `dim_sucursal[formato]` | 660 | 10 | 300 | 50 |
| Filtros | Segmentación (lista desplegable) | `dim_producto[departamento]` | 980 | 10 | 280 | 50 |
| KPIs | Tarjeta | `Ventas` | 20 | 70 | 240 | 90 |
| KPIs | Tarjeta | `Margen %` | 270 | 70 | 240 | 90 |
| KPIs | Tarjeta | `Tickets` | 520 | 70 | 240 | 90 |
| KPIs | Tarjeta | `Ticket promedio` | 770 | 70 | 240 | 90 |
| KPIs | Tarjeta | `Variación interanual %` | 1020 | 70 | 240 | 90 |
| 1 | Gráfico de líneas | Eje: `Calendario[Año-Mes]`; Valores: `Ventas`, `Ventas año anterior` | 20 | 170 | 620 | 270 |
| 1 | Barras horizontales | Eje: `dim_sucursal[sucursal]`; Valores: `Ventas` | 650 | 170 | 610 | 270 |
| 2 | Columnas | Eje: `Calendario[Día semana]`; Valores: `Ventas` | 20 | 450 | 410 | 260 |
| 2 | Barras horizontales | Eje: `dim_producto[departamento]`; Valores: `Ventas` | 440 | 450 | 410 | 260 |
| 2 | Columnas 100 % apiladas | Eje: `Calendario[Año-Trimestre]`; Leyenda: `fact_ventas[medio_pago]`; Valores: `Ventas` | 860 | 450 | 400 | 260 |

**Títulos:** "Ventas por mes vs. año anterior", "Ventas por sucursal", "Ventas por día de la semana", "Ventas por departamento", "Medios de pago por trimestre".

## Página 2: Inventario

Duplicá la página 1 (clic derecho en la pestaña > *Duplicar página*), borrá las visuales y armá estas:

| Fila | Visual | Campos | X | Y | Ancho | Alto |
|---|---|---|---|---|---|---|
| Filtros | Segmentación (lista desplegable) | `dim_sucursal[sucursal]` | 20 | 10 | 300 | 50 |
| Filtros | Segmentación (lista desplegable) | `dim_producto[departamento]` | 340 | 10 | 300 | 50 |
| Filtros | Segmentación (lista desplegable) | `dim_producto[categoria]` | 660 | 10 | 300 | 50 |
| Filtros | Segmentación (lista desplegable) | `dim_producto[proveedor]` | 980 | 10 | 280 | 50 |
| KPIs | Tarjeta | `Stock valorizado` | 20 | 70 | 240 | 90 |
| KPIs | Tarjeta | `Stock unidades` | 270 | 70 | 240 | 90 |
| KPIs | Tarjeta | `Pares bajo mínimo` | 520 | 70 | 240 | 90 |
| KPIs | Tarjeta | `% pares bajo mínimo` | 770 | 70 | 240 | 90 |
| KPIs | Tarjeta | `Días de cobertura` | 1020 | 70 | 240 | 90 |
| 1 | Barras horizontales | Eje: `dim_producto[categoria]`; Valores: `Stock valorizado` | 20 | 170 | 620 | 270 |
| 1 | Barras horizontales | Eje: `dim_producto[categoria]`; Valores: `Días de cobertura` | 650 | 170 | 610 | 270 |
| 2 | Tabla | `dim_sucursal[sucursal]`, `dim_producto[producto]`, `dim_producto[proveedor]`, `dim_producto[plazo_entrega_dias]`, `Stock unidades`, `Stock mínimo` | 20 | 450 | 1240 | 260 |

**Títulos:** "Stock valorizado por categoría (a costo)", "Días de cobertura por categoría", "Reposición urgente".

**Tabla de reposición:** en el panel *Filtros*, con la tabla seleccionada, agregá `fact_inventario[bajo_minimo]` a *Filtros de esta visual* y dejalo en **1**. Ordená por `Stock unidades` ascendente.

## Ajustes manuales que el tema no cubre
- **Gráfico de líneas:** ordenar el eje por `Año-Mes` ascendente (⋯ > Ordenar eje), desactivar el suavizado de línea y apagar el subtítulo automático.
- **Columnas por día de la semana:** ordenar por `Día semana N` (con la columna `Día semana` ordenada por esa otra) para que vaya de lunes a domingo.
- **Formato de números:** `Ventas`, `Margen`, `Ticket promedio` y `Stock valorizado` como moneda sin decimales; `Tickets`, `Stock unidades` y `Pares bajo mínimo` como entero con separador de miles; `Margen %`, `Variación interanual %` y `% pares bajo mínimo` como porcentaje con 1 decimal; `Días de cobertura` como entero.
- **Cobertura:** en las barras de `Días de cobertura`, ordenar de mayor a menor. Las categorías con más días son las de menor rotación.

## Cifras de control (datos con semilla 42, sin filtros)
Página 1: Ventas **$162.196.187** · Margen % **26,8 %** · Tickets **10.000** · Ticket promedio **$16.220**.
Página 2: Stock valorizado **$31.708.411** · Stock unidades **11.962** · Pares bajo mínimo **61** · % pares bajo mínimo **12,3 %**.
`% ventas de socios` debería dar **58,9 %** y `Unidades por ticket` **6,8**.
