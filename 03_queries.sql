-- ============================================================
-- 03_queries.sql  |  Consultas analíticas del retail (MySQL 8.0+)
-- Los importes salen siempre de detalle_ventas (venta neta de descuento).
-- Los porcentajes usan 100.0 para forzar división decimal.
-- ============================================================
USE retail_db;

-- ------------------------------------------------------------
-- 1. Desempeño por sucursal: ventas, margen, ventas por m² y ranking
-- ------------------------------------------------------------
SELECT
    s.nombre AS sucursal,
    s.formato,
    COUNT(DISTINCT v.venta_id) AS tickets,
    ROUND(SUM(d.importe), 0) AS ventas,
    ROUND(SUM(d.margen), 0) AS margen,
    ROUND(100.0 * SUM(d.margen) / SUM(d.importe), 1) AS margen_pct,
    ROUND(SUM(d.importe) / s.superficie_m2, 0) AS ventas_por_m2,
    RANK() OVER (ORDER BY SUM(d.importe) DESC) AS ranking_ventas,
    RANK() OVER (ORDER BY SUM(d.importe) / s.superficie_m2 DESC) AS ranking_por_m2
FROM ventas v
JOIN detalle_ventas d ON d.venta_id = v.venta_id
JOIN sucursales s ON s.sucursal_id = v.sucursal_id
GROUP BY s.sucursal_id, s.nombre, s.formato, s.superficie_m2
ORDER BY ventas DESC;

-- ------------------------------------------------------------
-- 2. CTE + LAG: ventas mensuales, variación mensual e interanual (nominal)
-- ------------------------------------------------------------
WITH mensual AS (
    SELECT
        DATE_FORMAT(v.fecha_hora, '%Y-%m') AS mes,
        SUM(d.importe) AS ventas,
        SUM(d.margen) AS margen
    FROM ventas v
    JOIN detalle_ventas d ON d.venta_id = v.venta_id
    GROUP BY DATE_FORMAT(v.fecha_hora, '%Y-%m')
)
SELECT
    mes,
    ROUND(ventas, 0) AS ventas,
    ROUND(100.0 * (ventas - LAG(ventas) OVER (ORDER BY mes))
          / LAG(ventas) OVER (ORDER BY mes), 1) AS var_mensual_pct,
    ROUND(100.0 * (ventas - LAG(ventas, 12) OVER (ORDER BY mes))
          / LAG(ventas, 12) OVER (ORDER BY mes), 1) AS var_interanual_pct,
    ROUND(100.0 * margen / ventas, 1) AS margen_pct
FROM mensual
ORDER BY mes;

-- ------------------------------------------------------------
-- 3. Top 10 productos por margen (no por ventas)
-- ------------------------------------------------------------
SELECT
    p.nombre AS producto,
    c.nombre_categoria AS categoria,
    SUM(d.cantidad) AS unidades,
    ROUND(SUM(d.importe), 0) AS ventas,
    ROUND(SUM(d.margen), 0) AS margen,
    ROUND(100.0 * SUM(d.margen) / SUM(d.importe), 1) AS margen_pct
FROM detalle_ventas d
JOIN productos p ON p.producto_id = d.producto_id
JOIN categorias c ON c.categoria_id = p.categoria_id
GROUP BY p.producto_id, p.nombre, c.nombre_categoria
ORDER BY margen DESC
LIMIT 10;

-- ------------------------------------------------------------
-- 4. Análisis ABC (Pareto): A = primeros 80 % de las ventas,
--    B = hasta el 95 %, C = el resto
-- ------------------------------------------------------------
WITH ventas_producto AS (
    SELECT p.producto_id, SUM(d.importe) AS ventas
    FROM detalle_ventas d
    JOIN productos p ON p.producto_id = d.producto_id
    GROUP BY p.producto_id
),
acumulado AS (
    SELECT
        producto_id,
        ventas,
        SUM(ventas) OVER (ORDER BY ventas DESC, producto_id) AS acum,
        SUM(ventas) OVER () AS total
    FROM ventas_producto
),
clasificado AS (
    SELECT
        ventas,
        CASE
            WHEN 1.0 * acum / total <= 0.80 THEN 'A'
            WHEN 1.0 * acum / total <= 0.95 THEN 'B'
            ELSE 'C'
        END AS clase
    FROM acumulado
)
SELECT
    clase,
    COUNT(*) AS productos,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_productos,
    ROUND(100.0 * SUM(ventas) / SUM(SUM(ventas)) OVER (), 1) AS pct_ventas
FROM clasificado
GROUP BY clase
ORDER BY clase;

-- ------------------------------------------------------------
-- 5. Ventas por día de la semana
-- ------------------------------------------------------------
WITH por_dia AS (
    SELECT
        DAYOFWEEK(v.fecha_hora) AS dow,
        COUNT(DISTINCT v.venta_id) AS tickets,
        SUM(d.importe) AS ventas
    FROM ventas v
    JOIN detalle_ventas d ON d.venta_id = v.venta_id
    GROUP BY DAYOFWEEK(v.fecha_hora)
)
SELECT
    CASE dow
        WHEN 1 THEN 'Domingo' WHEN 2 THEN 'Lunes' WHEN 3 THEN 'Martes'
        WHEN 4 THEN 'Miércoles' WHEN 5 THEN 'Jueves' WHEN 6 THEN 'Viernes'
        ELSE 'Sábado'
    END AS dia_semana,
    tickets,
    ROUND(ventas, 0) AS ventas,
    ROUND(100.0 * ventas / SUM(ventas) OVER (), 1) AS pct_ventas
FROM por_dia
ORDER BY (dow + 5) % 7;

-- ------------------------------------------------------------
-- 6. Ticket promedio por franja horaria
-- ------------------------------------------------------------
WITH tickets AS (
    SELECT
        v.venta_id,
        CASE
            WHEN HOUR(v.fecha_hora) < 12 THEN '1. Mañana (8 a 12 h)'
            WHEN HOUR(v.fecha_hora) < 17 THEN '2. Tarde (12 a 17 h)'
            ELSE '3. Noche (17 a 22 h)'
        END AS franja,
        SUM(d.importe) AS monto
    FROM ventas v
    JOIN detalle_ventas d ON d.venta_id = v.venta_id
    GROUP BY v.venta_id, v.fecha_hora
)
SELECT
    franja,
    COUNT(*) AS tickets,
    ROUND(SUM(monto), 0) AS ventas,
    ROUND(AVG(monto), 0) AS ticket_promedio
FROM tickets
GROUP BY franja
ORDER BY franja;

-- ------------------------------------------------------------
-- 7. Mix de medios de pago por trimestre
-- ------------------------------------------------------------
WITH trimestral AS (
    SELECT
        CONCAT(YEAR(v.fecha_hora), '-T', QUARTER(v.fecha_hora)) AS trimestre,
        v.medio_pago,
        SUM(d.importe) AS ventas
    FROM ventas v
    JOIN detalle_ventas d ON d.venta_id = v.venta_id
    GROUP BY CONCAT(YEAR(v.fecha_hora), '-T', QUARTER(v.fecha_hora)), v.medio_pago
)
SELECT
    trimestre,
    medio_pago,
    ROUND(100.0 * ventas / SUM(ventas) OVER (PARTITION BY trimestre), 1) AS pct_ventas
FROM trimestral
ORDER BY trimestre, pct_ventas DESC;

-- ------------------------------------------------------------
-- 8. Impacto de los descuentos en el margen
-- ------------------------------------------------------------
WITH lineas AS (
    SELECT
        CASE
            WHEN descuento_pct = 0 THEN 1
            WHEN descuento_pct <= 10 THEN 2
            WHEN descuento_pct <= 20 THEN 3
            ELSE 4
        END AS orden,
        CASE
            WHEN descuento_pct = 0 THEN 'Sin descuento'
            WHEN descuento_pct <= 10 THEN '5 a 10 %'
            WHEN descuento_pct <= 20 THEN '15 a 20 %'
            ELSE '25 %'
        END AS tramo,
        importe,
        margen
    FROM detalle_ventas
)
SELECT
    tramo,
    COUNT(*) AS lineas,
    ROUND(SUM(importe), 0) AS ventas,
    ROUND(100.0 * SUM(margen) / SUM(importe), 1) AS margen_pct,
    SUM(CASE WHEN margen < 0 THEN 1 ELSE 0 END) AS lineas_con_perdida,
    ROUND(100.0 * SUM(CASE WHEN margen < 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_con_perdida
FROM lineas
GROUP BY orden, tramo
ORDER BY orden;

-- ------------------------------------------------------------
-- 9. Socios vs. clientes sin identificar
-- ------------------------------------------------------------
WITH tickets AS (
    SELECT
        v.venta_id,
        CASE WHEN v.cliente_id IS NULL THEN 'Sin identificar' ELSE 'Socio' END AS tipo,
        SUM(d.importe) AS monto,
        SUM(d.cantidad) AS unidades
    FROM ventas v
    JOIN detalle_ventas d ON d.venta_id = v.venta_id
    GROUP BY v.venta_id, v.cliente_id
)
SELECT
    tipo,
    COUNT(*) AS tickets,
    ROUND(100.0 * SUM(monto) / SUM(SUM(monto)) OVER (), 1) AS pct_ventas,
    ROUND(AVG(monto), 0) AS ticket_promedio,
    ROUND(1.0 * SUM(unidades) / COUNT(*), 1) AS unidades_por_ticket
FROM tickets
GROUP BY tipo
ORDER BY pct_ventas DESC;

-- ------------------------------------------------------------
-- 10. Segmentación de socios por recencia y frecuencia (base de RFM)
--     Reciente = compró en los últimos 90 días; frecuente = 4 o más tickets.
--     Se usan umbrales fijos (y no NTILE) para que el resultado no dependa
--     de cómo cada motor desempata los clientes con la misma frecuencia.
-- ------------------------------------------------------------
WITH base AS (
    SELECT
        v.cliente_id,
        DATEDIFF((SELECT MAX(DATE(fecha_hora)) FROM ventas), MAX(DATE(v.fecha_hora))) AS recencia_dias,
        COUNT(DISTINCT v.venta_id) AS frecuencia,
        SUM(d.importe) AS monto
    FROM ventas v
    JOIN detalle_ventas d ON d.venta_id = v.venta_id
    WHERE v.cliente_id IS NOT NULL
    GROUP BY v.cliente_id
),
segmentos AS (
    SELECT
        cliente_id,
        monto,
        CASE
            WHEN recencia_dias <= 90 AND frecuencia >= 4 THEN 'Leales'
            WHEN recencia_dias <= 90 THEN 'Recientes (poca frecuencia)'
            WHEN frecuencia >= 4 THEN 'En riesgo (compraban seguido)'
            ELSE 'Dormidos'
        END AS segmento
    FROM base
)
SELECT
    segmento,
    COUNT(*) AS clientes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_clientes,
    ROUND(100.0 * SUM(monto) / SUM(SUM(monto)) OVER (), 1) AS pct_ventas,
    ROUND(AVG(monto), 0) AS gasto_promedio
FROM segmentos
GROUP BY segmento
ORDER BY pct_ventas DESC;

-- ------------------------------------------------------------
-- 11. Reposición urgente: productos en o bajo el stock mínimo,
--     con su proveedor y plazo de entrega (los 30 más críticos)
-- ------------------------------------------------------------
SELECT
    s.nombre AS sucursal,
    p.nombre AS producto,
    pr.nombre AS proveedor,
    pr.plazo_entrega_dias,
    i.stock_actual,
    i.stock_minimo,
    (i.stock_minimo * 2 - i.stock_actual) AS unidades_sugeridas_a_pedir
FROM inventario i
JOIN sucursales s ON s.sucursal_id = i.sucursal_id
JOIN productos p ON p.producto_id = i.producto_id
JOIN proveedores pr ON pr.proveedor_id = p.proveedor_id
WHERE i.stock_actual <= i.stock_minimo
ORDER BY 1.0 * i.stock_actual / i.stock_minimo, pr.plazo_entrega_dias DESC,
         i.sucursal_id, i.producto_id
LIMIT 30;

-- ------------------------------------------------------------
-- 12. Cobertura de stock por categoría: días que alcanza el stock
--     según las ventas de los últimos 90 días
-- ------------------------------------------------------------
WITH v90 AS (
    SELECT v.sucursal_id, d.producto_id, SUM(d.cantidad) AS unidades_90d
    FROM ventas v
    JOIN detalle_ventas d ON d.venta_id = v.venta_id
    WHERE v.fecha_hora > DATE_SUB((SELECT MAX(fecha_hora) FROM ventas), INTERVAL 90 DAY)
    GROUP BY v.sucursal_id, d.producto_id
)
SELECT
    c.nombre_categoria AS categoria,
    SUM(i.stock_actual) AS unidades_en_stock,
    ROUND(SUM(i.stock_actual * p.costo), 0) AS stock_valorizado,
    COALESCE(SUM(v90.unidades_90d), 0) AS unidades_vendidas_90d,
    ROUND(SUM(i.stock_actual) / (NULLIF(SUM(COALESCE(v90.unidades_90d, 0)), 0) / 90.0), 0) AS dias_de_cobertura
FROM inventario i
JOIN productos p ON p.producto_id = i.producto_id
JOIN categorias c ON c.categoria_id = p.categoria_id
LEFT JOIN v90 ON v90.sucursal_id = i.sucursal_id AND v90.producto_id = i.producto_id
GROUP BY c.categoria_id, c.nombre_categoria
ORDER BY dias_de_cobertura;
