# RPM spec for Querya Desktop (built via scripts/linux/build_rpm.sh).
# Macros querya_bundle, querya_icon, querya_desktop_file, and version are passed on the command line.

Name:           querya-desktop
Version:        %{version}
Release:        1%{?dist}
Summary:        Querya Desktop database client
License:        MIT
URL:            https://github.com/QueryaHub/Querya-Desktop
BuildArch:      x86_64
Requires:       gtk3 >= 3.22
Requires:       libsecret >= 0.18
Requires:       glib2 >= 2.56
Recommends:     libappindicator-gtk3

%description
Multi-database desktop client for PostgreSQL, MySQL, Redis, MongoDB,
SQLite, and sandboxed drivers.

%prep
# Pre-built Flutter bundle; no source compile in this packaging path.

%build
# no-op

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/opt/querya-desktop
cp -a %{querya_bundle}/. %{buildroot}/opt/querya-desktop/
chmod +x %{buildroot}/opt/querya-desktop/querya_desktop
mkdir -p %{buildroot}/usr/bin
ln -s /opt/querya-desktop/querya_desktop %{buildroot}/usr/bin/querya_desktop
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/512x512/apps
install -m 644 %{querya_desktop_file} %{buildroot}/usr/share/applications/querya_desktop.desktop
install -m 644 %{querya_icon} %{buildroot}/usr/share/icons/hicolor/512x512/apps/querya_desktop.png

%files
/opt/querya-desktop
/usr/bin/querya_desktop
/usr/share/applications/querya_desktop.desktop
/usr/share/icons/hicolor/512x512/apps/querya_desktop.png

%changelog
