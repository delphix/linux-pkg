#
# Copyright 2018 Delphix
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

.PHONY: clean prepare deb

METAPACKAGE_VERSION ?= 1.0.0

all:
	./prepare.sh

clean:
	@rm -rf etc/
	@rm -f depends
	@rm -rf artifacts

deb:
	rm -f debian/changelog
	DEBEMAIL="Delphix Engineering <eng@delphix.com>" \
		dch --create --package delphix-extra \
		-v "$(METAPACKAGE_VERSION)" \
		"Automatically generated changelog entry."
	dpkg-buildpackage -uc -us -b
	mkdir -p artifacts
	mv ../delphix-extra*.deb artifacts/
