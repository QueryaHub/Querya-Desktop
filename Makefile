# Querya Desktop

.PHONY: run build deps

# Зависимости Flutter
deps:
	flutter pub get

# Запуск приложения
run:
	flutter run

# Сборка (Linux)
build:
	flutter build linux

# Сборка Windows exe (Redis и остальное работают без Java)
build-windows:
	flutter build windows
