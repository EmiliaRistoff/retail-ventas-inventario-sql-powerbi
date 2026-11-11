-- ============================================================
-- 01_schema.sql  |  Cadena de supermercados (MySQL 8.0.16+)
-- ADVERTENCIA: este script ejecuta DROP DATABASE y borra retail_db
-- si ya existe. Los CHECK solo se aplican desde MySQL 8.0.16
-- (en versiones anteriores se ignoran en silencio).
-- ============================================================

DROP DATABASE IF EXISTS retail_db;
CREATE DATABASE retail_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE retail_db;

-- 1. Sucursales
CREATE TABLE sucursales (
    sucursal_id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(60) NOT NULL UNIQUE,
    ciudad VARCHAR(60) NOT NULL,
    provincia VARCHAR(40) NOT NULL,
    region VARCHAR(30) NOT NULL,
    formato ENUM('Hipermercado', 'Supermercado', 'Express') NOT NULL,
    superficie_m2 INT NOT NULL CHECK (superficie_m2 > 0),
    fecha_apertura DATE NOT NULL
) ENGINE=InnoDB;

-- 2. Categorías (con su departamento)
CREATE TABLE categorias (
    categoria_id INT AUTO_INCREMENT PRIMARY KEY,
    nombre_categoria VARCHAR(60) NOT NULL UNIQUE,
    departamento VARCHAR(60) NOT NULL
) ENGINE=InnoDB;

-- 3. Proveedores
CREATE TABLE proveedores (
    proveedor_id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    ciudad VARCHAR(60) NOT NULL,
    plazo_entrega_dias INT NOT NULL CHECK (plazo_entrega_dias > 0)
) ENGINE=InnoDB;

-- 4. Productos (catálogo)
-- costo y precio_lista son los valores ACTUALES. El precio y el costo al
-- momento de cada venta se guardan en detalle_ventas.
CREATE TABLE productos (
    producto_id INT AUTO_INCREMENT PRIMARY KEY,
    sku VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    categoria_id INT NOT NULL,
    proveedor_id INT NOT NULL,
    marca VARCHAR(50) NOT NULL,
    costo DECIMAL(10, 2) NOT NULL CHECK (costo > 0),
    precio_lista DECIMAL(10, 2) NOT NULL CHECK (precio_lista > 0),
    CONSTRAINT fk_producto_categoria FOREIGN KEY (categoria_id)
        REFERENCES categorias(categoria_id) ON DELETE RESTRICT,
    CONSTRAINT fk_producto_proveedor FOREIGN KEY (proveedor_id)
        REFERENCES proveedores(proveedor_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 5. Clientes (socios del programa de beneficios)
-- Una venta puede no tener cliente: es el caso del cliente no identificado.
CREATE TABLE clientes (
    cliente_id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    apellido VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    ciudad VARCHAR(60) NOT NULL,
    fecha_alta DATETIME NOT NULL
) ENGINE=InnoDB;

-- 6. Ventas (un registro por ticket)
-- No guarda el total: se calcula siempre desde detalle_ventas, que es la
-- única fuente de verdad de los importes.
CREATE TABLE ventas (
    venta_id INT AUTO_INCREMENT PRIMARY KEY,
    sucursal_id INT NOT NULL,
    cliente_id INT NULL,
    fecha_hora DATETIME NOT NULL,
    medio_pago ENUM('Efectivo', 'Débito', 'Crédito', 'Billetera virtual') NOT NULL,
    CONSTRAINT fk_venta_sucursal FOREIGN KEY (sucursal_id)
        REFERENCES sucursales(sucursal_id) ON DELETE RESTRICT,
    CONSTRAINT fk_venta_cliente FOREIGN KEY (cliente_id)
        REFERENCES clientes(cliente_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- 7. Detalle de ventas (una fila por producto del ticket)
-- importe: venta neta de descuento. margen: importe menos costo.
CREATE TABLE detalle_ventas (
    detalle_id INT AUTO_INCREMENT PRIMARY KEY,
    venta_id INT NOT NULL,
    producto_id INT NOT NULL,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_unitario DECIMAL(10, 2) NOT NULL CHECK (precio_unitario > 0),
    descuento_pct DECIMAL(5, 2) NOT NULL DEFAULT 0 CHECK (descuento_pct BETWEEN 0 AND 100),
    costo_unitario DECIMAL(10, 2) NOT NULL CHECK (costo_unitario > 0),
    importe DECIMAL(12, 2) GENERATED ALWAYS AS
        (ROUND(cantidad * precio_unitario * (100 - descuento_pct) / 100.0, 2)) STORED,
    margen DECIMAL(12, 2) GENERATED ALWAYS AS
        (ROUND(cantidad * precio_unitario * (100 - descuento_pct) / 100.0 - cantidad * costo_unitario, 2)) STORED,
    CONSTRAINT fk_detalle_venta FOREIGN KEY (venta_id)
        REFERENCES ventas(venta_id) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (producto_id)
        REFERENCES productos(producto_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 8. Inventario (foto actual del stock por sucursal y producto)
-- Cada sucursal maneja solo su surtido: el Express no vende electro ni mascotas.
CREATE TABLE inventario (
    sucursal_id INT NOT NULL,
    producto_id INT NOT NULL,
    stock_actual INT NOT NULL CHECK (stock_actual >= 0),
    stock_minimo INT NOT NULL CHECK (stock_minimo >= 0),
    PRIMARY KEY (sucursal_id, producto_id),
    CONSTRAINT fk_inventario_sucursal FOREIGN KEY (sucursal_id)
        REFERENCES sucursales(sucursal_id) ON DELETE CASCADE,
    CONSTRAINT fk_inventario_producto FOREIGN KEY (producto_id)
        REFERENCES productos(producto_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Índices para las consultas analíticas (las FK ya generan los suyos en InnoDB)
CREATE INDEX idx_ventas_fecha ON ventas (fecha_hora);
CREATE INDEX idx_ventas_medio ON ventas (medio_pago);

-- ============================================================
-- ESQUEMA EN ESTRELLA PARA POWER BI
-- Las vistas "vw_fact_*" son tablas de hechos (eventos medibles) y las
-- "vw_dim_*" son dimensiones (los ejes por los que se analiza).
-- ============================================================

-- Hechos: una fila por línea de ticket
CREATE VIEW vw_fact_ventas AS
SELECT
    d.detalle_id,
    v.venta_id,
    DATE(v.fecha_hora) AS fecha,
    HOUR(v.fecha_hora) AS hora,
    v.sucursal_id,
    v.cliente_id,
    d.producto_id,
    v.medio_pago,
    d.cantidad,
    d.precio_unitario,
    d.descuento_pct,
    d.costo_unitario,
    d.importe,
    d.cantidad * d.costo_unitario AS costo_total,
    d.margen
FROM detalle_ventas d
JOIN ventas v ON v.venta_id = d.venta_id;

-- Hechos: foto de inventario, con valorización y marca de stock bajo
CREATE VIEW vw_fact_inventario AS
SELECT
    i.sucursal_id,
    i.producto_id,
    i.stock_actual,
    i.stock_minimo,
    ROUND(i.stock_actual * p.costo, 2) AS stock_valorizado,
    CASE WHEN i.stock_actual <= i.stock_minimo THEN 1 ELSE 0 END AS bajo_minimo
FROM inventario i
JOIN productos p ON p.producto_id = i.producto_id;

-- Dimensión producto: aplana categoría, departamento y proveedor
CREATE VIEW vw_dim_producto AS
SELECT
    p.producto_id,
    p.sku,
    p.nombre AS producto,
    p.marca,
    c.nombre_categoria AS categoria,
    c.departamento,
    pr.nombre AS proveedor,
    pr.plazo_entrega_dias,
    p.costo,
    p.precio_lista
FROM productos p
JOIN categorias c ON c.categoria_id = p.categoria_id
JOIN proveedores pr ON pr.proveedor_id = p.proveedor_id;

-- Dimensión sucursal
CREATE VIEW vw_dim_sucursal AS
SELECT
    sucursal_id,
    nombre AS sucursal,
    ciudad,
    provincia,
    region,
    formato,
    superficie_m2,
    fecha_apertura
FROM sucursales;

-- Dimensión cliente
CREATE VIEW vw_dim_cliente AS
SELECT
    cliente_id,
    CONCAT(nombre, ' ', apellido) AS cliente,
    ciudad,
    fecha_alta
FROM clientes;
