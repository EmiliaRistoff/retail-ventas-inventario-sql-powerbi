#!/usr/bin/env python3
"""
Genera 02_seed_data.sql para el proyecto retail_db (cadena de supermercados ficticia).

- Solo usa la libreria estandar (sin dependencias).
- Es reproducible: misma semilla => mismo archivo.
- Garantiza coherencia: stock >= 0, ningun cliente se da de alta despues de su
  primera compra, sin productos repetidos dentro de un ticket y cada sucursal
  vende solo los productos de su surtido.

Uso:
    python generate_seed.py
    python generate_seed.py --tickets 30000 --clientes 6000 --seed 7
"""
import argparse
import math
import random
from datetime import datetime, timedelta

ap = argparse.ArgumentParser()
ap.add_argument("--clientes", type=int, default=2500)
ap.add_argument("--tickets", type=int, default=10000)
ap.add_argument("--seed", type=int, default=42)
ap.add_argument("--salida", default="02_seed_data.sql")
args = ap.parse_args()
random.seed(args.seed)

FECHA_INI = datetime(2025, 1, 1)
FECHA_FIN = datetime(2026, 10, 31)
INFLACION_MENSUAL = 0.025

# ------------------------------- Maestros -----------------------------------
# (nombre, ciudad, provincia, region, formato, m2, apertura, peso_de_trafico)
SUCURSALES = [
    ("Palermo", "Ciudad de Buenos Aires", "CABA", "AMBA", "Supermercado", 2400, "2016-03-15", 20),
    ("La Plata Centro", "La Plata", "Buenos Aires", "AMBA", "Hipermercado", 3200, "2018-08-20", 18),
    ("Rosario Centro", "Rosario", "Santa Fe", "Centro", "Supermercado", 2800, "2017-05-10", 15),
    ("Córdoba Cerro", "Córdoba", "Córdoba", "Centro", "Supermercado", 2600, "2019-11-02", 14),
    ("Mendoza Ciudad", "Mendoza", "Mendoza", "Cuyo", "Supermercado", 2200, "2020-04-18", 10),
    ("Tucumán Centro", "San Miguel de Tucumán", "Tucumán", "NOA", "Supermercado", 1900, "2021-09-09", 8),
    ("Mar del Plata", "Mar del Plata", "Buenos Aires", "Costa Atlántica", "Express", 700, "2022-01-25", 7),
    ("Bariloche Centro", "San Carlos de Bariloche", "Río Negro", "Patagonia", "Express", 650, "2023-06-12", 5),
]
# categorias excluidas por formato (id de categoria)
EXCLUIDAS = {"Hipermercado": set(), "Supermercado": {12}, "Express": {10, 11, 12}}

# (categoria, departamento, margen_medio_sobre_precio, peso_en_ticket, items[(nombre, precio_lista)])
CATEGORIAS = [
    ("Lácteos y Fiambres", "Alimentos", 0.22, 14, [("Leche entera 1L", 1900), ("Yogur firme 1L", 2300), ("Queso cremoso x kg", 9800), ("Manteca 200g", 3400), ("Jamón cocido x 200g", 4200), ("Dulce de leche 400g", 3100)]),
    ("Almacén", "Alimentos", 0.26, 16, [("Arroz largo fino 1kg", 2400), ("Fideos guiseros 500g", 1700), ("Aceite de girasol 900ml", 3600), ("Harina 000 1kg", 1500), ("Azúcar 1kg", 1900), ("Yerba mate 1kg", 5200), ("Café molido 250g", 4800), ("Puré de tomate 520g", 1300)]),
    ("Panadería y Galletitas", "Alimentos", 0.30, 10, [("Pan lactal 500g", 2800), ("Galletitas dulces 300g", 1900), ("Galletitas de agua 300g", 1600), ("Medialunas x6", 3500), ("Alfajores x6", 4100), ("Tostadas 200g", 1700)]),
    ("Carnes y Congelados", "Alimentos", 0.18, 10, [("Asado x kg", 12500), ("Milanesas de pollo x kg", 8900), ("Hamburguesas x4", 5200), ("Pechuga x kg", 7800), ("Papas fritas congeladas 700g", 3300), ("Helado 1L", 6200)]),
    ("Frutas y Verduras", "Alimentos", 0.35, 12, [("Banana x kg", 2600), ("Manzana x kg", 3100), ("Tomate x kg", 3800), ("Papa x kg", 1800), ("Cebolla x kg", 1500), ("Lechuga x unidad", 2100)]),
    ("Bebidas sin alcohol", "Bebidas", 0.28, 9, [("Gaseosa cola 2,25L", 3600), ("Agua mineral 2L", 1500), ("Jugo concentrado 1L", 2900), ("Soda 1,5L", 1100), ("Agua saborizada 1,5L", 1700), ("Energizante 473ml", 2800)]),
    ("Bebidas con alcohol", "Bebidas", 0.30, 4, [("Vino tinto 750ml", 6900), ("Cerveza lata 473ml", 1900), ("Fernet 750ml", 14500), ("Espumante 750ml", 9800), ("Gin 750ml", 16500)]),
    ("Limpieza", "Limpieza y Perfumería", 0.32, 7, [("Detergente 750ml", 2900), ("Lavandina 1L", 1400), ("Limpiador de pisos 900ml", 2600), ("Jabón en polvo 800g", 5800), ("Suavizante 900ml", 3700), ("Papel higiénico x4", 3900)]),
    ("Cuidado personal", "Limpieza y Perfumería", 0.38, 5, [("Shampoo 400ml", 4800), ("Jabón de tocador x3", 2900), ("Desodorante 150ml", 3900), ("Pasta dental 90g", 2300), ("Crema corporal 400ml", 6200), ("Protector solar 200ml", 11800)]),
    ("Bazar y Hogar", "Hogar y Mascotas", 0.42, 2, [("Set de vasos x6", 6800), ("Sartén antiadherente 24cm", 19800), ("Repasador x3", 4200), ("Frasco hermético 1L", 3600)]),
    ("Mascotas", "Hogar y Mascotas", 0.27, 3, [("Alimento perro adulto 15kg", 42000), ("Alimento gato 3kg", 16500), ("Piedras sanitarias 4kg", 7400), ("Snacks para perro 200g", 4100)]),
    ("Electro y Tecnología", "Electro", 0.25, 1.5, [("Auriculares básicos", 16900), ("Cargador USB 20W", 12500), ("Pilas AA x4", 3900), ("Lámpara LED 9W", 2800), ("Parlante Bluetooth", 38500), ("Ventilador de mesa", 52000)]),
]

# (nombre, ciudad, plazo_entrega_dias, categorias que abastece)
PROVEEDORES = [
    ("Lácteos Pampeanos S.A.", "Rafaela", 2, [1]),
    ("Molinos Santa Rosa", "Rosario", 4, [2]),
    ("Panificadora La Espiga", "Buenos Aires", 1, [3]),
    ("Frigorífico Los Álamos", "Pergamino", 3, [4]),
    ("Verduras del Valle", "Mendoza", 1, [5]),
    ("Bebidas del Litoral", "Santa Fe", 5, [6]),
    ("Bodegas Altos de Cuyo", "Mendoza", 6, [7]),
    ("Limpieza Total S.R.L.", "Avellaneda", 4, [8]),
    ("Perfumería Andina", "Córdoba", 5, [9]),
    ("Hogar y Más", "Buenos Aires", 7, [10]),
    ("Pet Center Argentina", "San Martín", 6, [11]),
    ("ElectroTec Import", "Buenos Aires", 10, [12]),
]
MARCAS = ["Campo Claro", "Sol de Mayo", "Don Rufino", "Aurora", "Vita", "Tierra Buena", "Brisa", "Nube", "La Serrana", "Pampa"]
NOMBRES = ["Juan", "María", "Carlos", "Ana", "Lucas", "Sofía", "Martín", "Lucía", "Diego", "Valentina", "Pablo", "Camila", "Nicolás", "Julieta", "Federico", "Florencia", "Matías", "Agustina", "Sebastián", "Paula", "Tomás", "Carolina"]
APELLIDOS = ["Pérez", "Gómez", "López", "Martínez", "Rodríguez", "Fernández", "García", "González", "Sánchez", "Romero", "Díaz", "Álvarez", "Torres", "Ruiz", "Acosta", "Benítez", "Medina", "Herrera", "Suárez", "Molina"]

# ------------------------------- Helpers ------------------------------------
def q(s):
    return "'" + str(s).replace("\\", "\\\\").replace("'", "''") + "'"

def fdt(d):
    return d.strftime("%Y-%m-%d %H:%M:%S")

def deflactar(valor, fecha):
    meses = (FECHA_FIN.year - fecha.year) * 12 + (FECHA_FIN.month - fecha.month)
    return round(valor / ((1 + INFLACION_MENSUAL) ** meses), 2)

# ------------------------------- Productos ----------------------------------
# productos de la canasta basica: se compran mucho mas seguido que el resto
BASICOS = {"Leche entera 1L", "Pan lactal 500g", "Yerba mate 1kg", "Fideos guiseros 500g",
           "Arroz largo fino 1kg", "Aceite de girasol 900ml", "Azúcar 1kg", "Harina 000 1kg",
           "Banana x kg", "Papa x kg", "Cebolla x kg", "Agua mineral 2L", "Gaseosa cola 2,25L",
           "Galletitas dulces 300g", "Papel higiénico x4"}
# estacionalidad (hemisferio sur): factor de verano; en invierno se aplica la inversa
VERANO = {"Protector solar 200ml": 5.0, "Helado 1L": 3.0, "Ventilador de mesa": 4.0,
          "Cerveza lata 473ml": 1.8, "Agua saborizada 1,5L": 1.8, "Soda 1,5L": 1.5}

def estacional(nombre, mes):
    f = VERANO.get(nombre)
    if f is None:
        return 1.0
    if mes in (12, 1, 2):
        return f
    if mes in (6, 7, 8):
        return 1.0 / f
    return 1.0

categorias = [(i, c[0], c[1]) for i, c in enumerate(CATEGORIAS, start=1)]
prov_de_cat = {}
for pid, (_, _, _, cats) in enumerate(PROVEEDORES, start=1):
    for c in cats:
        prov_de_cat[c] = pid

productos = []   # (id, sku, nombre, cat_id, prov_id, marca, costo, precio_lista, peso)
pid = 0
for cid, (cat, dep, margen, peso_cat, items) in enumerate(CATEGORIAS, start=1):
    for nombre, precio in items:
        pid += 1
        m = max(0.12, min(0.5, margen + random.uniform(-0.05, 0.05)))
        costo = round(precio * (1 - m), 2)
        peso = peso_cat / len(items) * random.lognormvariate(0, 0.7) * (3000 / precio) ** 0.6  # lo barato se compra mas seguido
        if nombre in BASICOS:
            peso *= 2.5
        productos.append((pid, f"SKU-{pid:04d}", nombre, cid, prov_de_cat[cid],
                          random.choice(MARCAS), costo, float(precio), peso))
cat_de_prod = {p[0]: p[3] for p in productos}

# surtido por sucursal
surtido = []
for nombre, ciudad, prov, region, formato, m2, ap_, trafico in SUCURSALES:
    ids = [p for p in productos if p[3] not in EXCLUIDAS[formato]]
    surtido.append(ids)

pesos_mes = {(s, m): [p[8] * estacional(p[2], m) for p in surtido[s]]
             for s in range(len(SUCURSALES)) for m in range(1, 13)}

# ------------------------------- Clientes -----------------------------------
suc_pesos = [s[7] for s in SUCURSALES]
clientes = []   # (id, nombre, apellido, email, ciudad, home_store_idx)
for i in range(1, args.clientes + 1):
    home = random.choices(range(len(SUCURSALES)), weights=suc_pesos)[0]
    nom, ape = random.choice(NOMBRES), random.choice(APELLIDOS)
    email = f"{nom}.{ape}{i}@email.com".lower()
    for a, b in (("á", "a"), ("é", "e"), ("í", "i"), ("ó", "o"), ("ú", "u"), ("ñ", "n")):
        email = email.replace(a, b)
    clientes.append((i, nom, ape, email, SUCURSALES[home][1], home))

por_sucursal = {s: [] for s in range(len(SUCURSALES))}
for c in clientes:
    por_sucursal[c[5]].append(c[0])
pesos_cli = {}
for s, ids in por_sucursal.items():
    pesos_cli[s] = [1 / ((k + 1) ** 0.5) for k in range(len(ids))]
    random.shuffle(pesos_cli[s])

# ------------------------------- Calendario de ventas -----------------------
dias, pesos_dia = [], []
PESO_DOW = {0: 0.85, 1: 0.8, 2: 0.85, 3: 0.95, 4: 1.2, 5: 1.5, 6: 1.1}
PESO_MES = {1: 0.9, 2: 0.85, 3: 0.95, 4: 0.95, 5: 1.0, 6: 1.0, 7: 1.05, 8: 0.95, 9: 1.0, 10: 1.05, 11: 1.15, 12: 1.5}
total_dias = (FECHA_FIN - FECHA_INI).days
d = FECHA_INI
while d <= FECHA_FIN:
    prog = (d - FECHA_INI).days / total_dias
    dias.append(d)
    pesos_dia.append(PESO_DOW[d.weekday()] * PESO_MES[d.month] * (1 + 0.25 * prog))
    d += timedelta(days=1)

HORAS = list(range(8, 22))
PESO_HORA = [3, 5, 8, 10, 9, 7, 6, 6, 8, 10, 11, 9, 6, 3]

fechas = sorted(random.choices(dias, weights=pesos_dia, k=args.tickets))

# ------------------------------- Tickets y detalle --------------------------
ventas, detalles = [], []
unidades90 = {}      # (sucursal_idx, prod_id) -> unidades en los ultimos 90 dias
primera_compra = {}
detalle_id = 0
corte90 = FECHA_FIN - timedelta(days=90)

for venta_id, dia in enumerate(fechas, start=1):
    fecha = dia.replace(hour=random.choices(HORAS, weights=PESO_HORA)[0],
                        minute=random.randint(0, 59), second=random.randint(0, 59))
    s_idx = random.choices(range(len(SUCURSALES)), weights=suc_pesos)[0]

    cliente_id = None
    if random.random() < 0.55:
        if random.random() < 0.92 and por_sucursal[s_idx]:
            cliente_id = random.choices(por_sucursal[s_idx], weights=pesos_cli[s_idx])[0]
        else:
            cliente_id = random.randint(1, args.clientes)
        primera_compra.setdefault(cliente_id, fecha)

    prog = (dia - FECHA_INI).days / total_dias
    medio = random.choices(["Efectivo", "Débito", "Crédito", "Billetera virtual"],
                           weights=[34 - 14 * prog, 32, 26, 8 + 20 * prog])[0]
    ventas.append((venta_id, s_idx + 1, cliente_id, fecha, medio))

    pesos_items = [9, 14, 16, 15, 12, 10, 9, 7, 5, 3] if cliente_id is not None \
        else [14, 18, 17, 14, 11, 9, 7, 5, 3, 2]
    n_items = random.choices(range(1, 11), weights=pesos_items)[0]
    candidatos = surtido[s_idx]
    elegidos = random.choices(candidatos, weights=pesos_mes[(s_idx, dia.month)], k=n_items)
    vistos = set()
    for p in elegidos:
        if p[0] in vistos:
            continue
        vistos.add(p[0])
        detalle_id += 1
        cant = random.choices([1, 2, 3, 4, 6], weights=[60, 22, 10, 5, 3])[0]
        if p[7] > 30000:
            cant = 1
        desc = random.choices([0, 5, 10, 15, 20, 25], weights=[80, 6, 7, 4, 2, 1])[0]
        detalles.append((detalle_id, venta_id, p[0], cant,
                         deflactar(p[7], fecha), desc, deflactar(p[6], fecha)))
        if fecha > corte90:
            k = (s_idx, p[0])
            unidades90[k] = unidades90.get(k, 0) + cant

# ------------------------------- Altas de clientes --------------------------
altas = {}
for c in clientes:
    cid = c[0]
    if cid in primera_compra:
        altas[cid] = primera_compra[cid] - timedelta(days=random.randint(0, 45),
                                                      seconds=random.randint(0, 3600))
    else:
        altas[cid] = FECHA_INI + timedelta(days=random.randint(0, total_dias),
                                           seconds=random.randint(0, 86399))
assert all(altas[c] <= f for c, f in primera_compra.items()), "Alta posterior a la primera compra"

# ------------------------------- Inventario ---------------------------------
inventario = []   # (sucursal_id, producto_id, stock_actual, stock_minimo)
for s_idx in range(len(SUCURSALES)):
    for p in surtido[s_idx]:
        u90 = unidades90.get((s_idx, p[0]), 0)
        minimo = max(4, round(u90 / 90 * 10))
        if random.random() < 0.12:
            actual = random.randint(0, minimo)
        else:
            actual = minimo + int(u90 * random.uniform(0.2, 1.5)) + random.randint(1, 8)
        inventario.append((s_idx + 1, p[0], actual, minimo))
assert all(i[2] >= 0 for i in inventario)

# ------------------------------- Escritura ----------------------------------
def insertar(f, tabla, cols, filas, lote=1000):
    for i in range(0, len(filas), lote):
        f.write(f"INSERT INTO {tabla} ({', '.join(cols)}) VALUES\n")
        f.write(",\n".join("(" + ", ".join(fila) + ")" for fila in filas[i:i + lote]))
        f.write(";\n\n")

with open(args.salida, "w", encoding="utf-8") as f:
    f.write("-- ============================================================\n")
    f.write("-- 02_seed_data.sql  (generado con generate_seed.py)\n")
    f.write(f"-- Sucursales: {len(SUCURSALES)} | Productos: {len(productos)} | Clientes: {len(clientes)} | "
            f"Tickets: {len(ventas)} | Líneas: {len(detalles)} | Inventario: {len(inventario)}\n")
    f.write(f"-- Datos 100% ficticios. Reproducible con --seed {args.seed}\n")
    f.write("-- ============================================================\n\n")
    f.write("USE retail_db;\n\n")

    insertar(f, "sucursales", ["sucursal_id", "nombre", "ciudad", "provincia", "region", "formato", "superficie_m2", "fecha_apertura"],
             [[str(i), q(s[0]), q(s[1]), q(s[2]), q(s[3]), q(s[4]), str(s[5]), q(s[6])] for i, s in enumerate(SUCURSALES, start=1)])
    insertar(f, "categorias", ["categoria_id", "nombre_categoria", "departamento"],
             [[str(i), q(n), q(dep)] for i, n, dep in categorias])
    insertar(f, "proveedores", ["proveedor_id", "nombre", "ciudad", "plazo_entrega_dias"],
             [[str(i), q(p[0]), q(p[1]), str(p[2])] for i, p in enumerate(PROVEEDORES, start=1)])
    insertar(f, "productos", ["producto_id", "sku", "nombre", "categoria_id", "proveedor_id", "marca", "costo", "precio_lista"],
             [[str(p[0]), q(p[1]), q(p[2]), str(p[3]), str(p[4]), q(p[5]), f"{p[6]:.2f}", f"{p[7]:.2f}"] for p in productos])
    insertar(f, "clientes", ["cliente_id", "nombre", "apellido", "email", "ciudad", "fecha_alta"],
             [[str(c[0]), q(c[1]), q(c[2]), q(c[3]), q(c[4]), q(fdt(altas[c[0]]))] for c in clientes])
    insertar(f, "ventas", ["venta_id", "sucursal_id", "cliente_id", "fecha_hora", "medio_pago"],
             [[str(v[0]), str(v[1]), "NULL" if v[2] is None else str(v[2]), q(fdt(v[3])), q(v[4])] for v in ventas])
    insertar(f, "detalle_ventas", ["detalle_id", "venta_id", "producto_id", "cantidad", "precio_unitario", "descuento_pct", "costo_unitario"],
             [[str(d[0]), str(d[1]), str(d[2]), str(d[3]), f"{d[4]:.2f}", f"{d[5]:.2f}", f"{d[6]:.2f}"] for d in detalles])
    insertar(f, "inventario", ["sucursal_id", "producto_id", "stock_actual", "stock_minimo"],
             [[str(i[0]), str(i[1]), str(i[2]), str(i[3])] for i in inventario])

bajo = sum(1 for i in inventario if i[2] <= i[3])
print(f"OK -> {args.salida}")
print(f"  sucursales={len(SUCURSALES)} productos={len(productos)} clientes={len(clientes)} tickets={len(ventas)} lineas={len(detalles)} inventario={len(inventario)}")
print(f"  pares sucursal-producto bajo el minimo={bajo}  tickets con cliente={sum(1 for v in ventas if v[2])}")
