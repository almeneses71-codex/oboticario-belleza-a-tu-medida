# Actualización semanal del catálogo

La fuente que consume la aplicación es `assets/data/products.json`.

Por cada actualización:

1. Duplica el archivo vigente como respaldo del ciclo anterior.
2. Actualiza `priceCop`, `available`, `eligible` y `updated`.
3. No cambies un `id` existente para representar otro producto.
4. Mantén los kits separados y recalcula su precio cuando cambien componentes.
5. Valida cada código y precio contra el catálogo fuente.
6. Ejecuta todas las pruebas antes de publicar.

Para ocultar un agotado, establece `available` y `eligible` en `false`. No borres el registro.

