# NotasApp - Gestión Universitaria

Aplicación móvil minimalista, 100% offline, diseñada para que estudiantes universitarios gestionen sus ramos, calificaciones y simulen qué notas necesitan para aprobar sus asignaturas. Construida con **Flutter**, **Riverpod**, y **SQLite** (Clean Architecture).

---

## 📥 Descargar APK (Versiones)

Encuentra a continuación el historial de versiones de la aplicación y su correspondiente archivo APK para instalar directamente en Android.
### [v1.0.5] - Actualizador inteligente, Fix Horarios y Permisos
**Fecha**: Julio 2026

**📦 Enlace de Descarga:** [NotasApp-v1.0.5.apk](./releases/notas-v1.0.5.apk)

**Novedades y Correcciones:**
- **Sistema de Actualización**: Se mejoró el algoritmo de detección de nuevas versiones. Las versiones anteriores solo detectaban los primeros 3 números (ej. `1.0.4`), pero ahora soporta cualquier longitud de versión para hotfixes (`1.0.4.1`, `1.0.5`, etc).
- **Interfaz Arreglada**: Se ajustó la altura del botón para añadir clases para evitar que sea tapado por la burbuja de navegación.
- **Ramos Inteligentes**: Ahora al añadir una clase al horario, el sistema solo te permite elegir entre los ramos creados previamente para el semestre seleccionado, evitando errores tipográficos.
- **Notificaciones 100% Funcionales (Android 14)**: Se adaptó el sistema para solicitar explícitamente el permiso de "Alarmas exactas y recordatorios" (`SCHEDULE_EXACT_ALARM`), solucionando el problema por el cual las notificaciones del horario no sonaban en Android 12 y superior.

---

### [v1.0.4] - Horario de Clases y Notificaciones
**Fecha**: Julio 2026

**📦 Enlace de Descarga:** [NotasApp-v1.0.4.apk](./releases/notas-v1.0.4.apk)

**Novedades y Características:**
- **Horario de Clases**: Nueva pestaña para visualizar tu horario universitario distribuido en bloques y por día de la semana.
- **Notificaciones 15 min antes**: Agrega tus clases a los bloques y recibe un aviso inteligente antes de que empiecen.
- **Mejoras en la Agenda**: Las evaluaciones en la agenda ahora están ordenadas mes a mes.
- **Alertas de Pruebas**: Nuevos recordatorios automáticos 24 horas y 12 horas antes de cada certamen.
- **Gestión de Permisos**: Nuevo menú en Configuración para activar/desactivar notificaciones fácilmente.

---

### [v1.0.3] - Agenda y Rediseño de Navegación
**Fecha**: Julio 2026

**📦 Enlace de Descarga:** [NotasApp-v1.0.3.apk](./releases/notas-v1.0.3.apk)

**Novedades y Características:**
- **Pestañas de Navegación**: Nuevo selector horizontal de semestres en la vista principal y burbuja de navegación inferior.
- **Agenda de Evaluaciones**: Nueva vista dedicada para organizar cronológicamente todas tus evaluaciones y sus fechas.
- **Widget de Android Mejorado**: Diseño más moderno con esquinas redondeadas y soporte para hora detallada de las evaluaciones.
- **Actualizaciones Silenciosas**: Sistema de notificaciones en segundo plano para avisarte de futuras actualizaciones.

---

### [v1.0.1] - Mejoras de Calidad de Vida (QoL)
**Fecha**: Julio 2026

**📦 Enlace de Descarga:** [NotasApp-v1.0.1.apk](./releases/v1.0.1/NotasApp-v1.0.1.apk)

**Novedades y Características:**
- **Modo de Selección Múltiple**: Ahora puedes mantener presionado un Semestre o Ramo para entrar en un modo de selección, permitiendo eliminar múltiples elementos a la vez.
- **Edición Rápida**: Renombra Semestres y re-configura Ramos directamente desde la barra contextual superior al seleccionar un único elemento.
- **Limpieza de Interfaz**: Se removió el recuadro redundante de nota "Necesaria" dentro de los detalles del ramo, dando más espacio a la nota actual y un aspecto más limpio.
- **Actualizador Integrado**: Funcionalidad de auto-actualización probada y activa para las futuras versiones.

---

### [v1.0.0] - Lanzamiento Inicial y Mejoras Core
**Fecha**: Julio 2026

**📦 Enlace de Descarga:** [NotasApp-v1.0.0.apk](./releases/v1.0.0/NotasApp-v1.0.0.apk)

**Novedades y Características:**
- **Sistema de Notas Personalizable**: Opción de seleccionar sistema de notas de 1 a 7 o de 0 a 100 en la configuración.
- **Modo Oscuro Integrado**: Tematización inteligente que ajusta dinámicamente toda la interfaz visual.
- **Jerarquía Avanzada de Notas**: Creación de *Grupos de Evaluación* con un porcentaje global. Las notas dentro de los grupos pueden dividirse equitativamente o tener porcentajes específicos.
- **Control al 100%**: Validación algorítmica para asegurar que las notas de un ramo nunca superen el 100% de la ponderación total.
- **Aprobación Condicionada**: Posibilidad de exigir una nota mínima de aprobación por Categoría, y no solo por Ramo.
- **Edición Rápida (Inline)**: Escribe y modifica notas directamente desde la lista principal del ramo y visualiza el recálculo instantáneo.
- **Diseño Monocromático**: Interfaz premium, limpia y enfocada con alertas de color verde/rojo dependiendo si la nota necesaria se ha alcanzado.
- **Totalmente Offline**: Todo se guarda localmente usando bases de datos `sqflite`.

---

## 🚀 Empezar a Desarrollar Localmente

### Prerrequisitos
- Flutter SDK (v3.22 o superior)
- Dart SDK
- Android Studio / VS Code

### Instalación
1. Clona el repositorio.
2. Instala las dependencias:
   ```bash
   flutter pub get
   ```
3. Ejecuta la aplicación:
   ```bash
   flutter run
   ```

## 🛠 Tecnologías Principales
- **Framework**: Flutter.
- **Gestión de Estado**: Riverpod (v3.x).
- **Base de Datos**: SQLite (mediante la librería `sqflite`).
- **Iconografía**: Generado mediante `flutter_launcher_icons`.

## 📁 Estructura del Proyecto
- `lib/models`: Entidades de la base de datos y la lógica matemática pura (Ramo, Evaluación, CategoriaEvaluacion).
- `lib/viewmodels`: Providers de Riverpod manejando el estado, la inyección de dependencias y el acceso asíncrono a SQLite.
- `lib/views`: Interfaz de Usuario y widgets (Scaffolds, listados, modales de ingreso).
- `lib/services`: Control de la conexión y esquemas de Base de Datos.
- `releases/`: Directorio donde se almacenan y distribuyen los APKs de manera pública.