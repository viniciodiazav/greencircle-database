-- =============================================================================
-- Módulo 04: Tabla de Sucursales
-- Descripción: Registro de sucursales / centros de acopio.
--              Tabla totalmente mutable y sin restricciones adicionales.
-- =============================================================================

CREATE TABLE IF NOT EXISTS sucursales (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    url TEXT
);

-- Comentarios explicativos en el catálogo de PostgreSQL
COMMENT ON TABLE sucursales IS 'Sucursales y centros de acopio del centro de reciclaje';
COMMENT ON COLUMN sucursales.id IS 'Identificador único incremental de la sucursal';
COMMENT ON COLUMN sucursales.nombre IS 'Nombre representativo de la sucursal';
COMMENT ON COLUMN sucursales.url IS 'URL o enlace web/mapa asociado a la sucursal';
