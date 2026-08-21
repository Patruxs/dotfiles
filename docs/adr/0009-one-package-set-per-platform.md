# One Package Set Per Platform

Each platform setup owns one package-set file that maps feature names to that platform's direct package or app entries. A run loads only the package set for the selected platform, preventing Ubuntu setup from reading Fedora, Arch, macOS, or Windows package data.
