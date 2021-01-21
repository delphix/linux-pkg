#
# Copyright 2018, 2019 Delphix
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

.PHONY: \
	clean \
	shellcheck \
	shfmtcheck \
	check \
	default

default:
	@echo 'This Makefile is only used for cleaning the repository and'
	@echo 'running the style checks. To build packages, first run'
	@echo './setup.sh, then run ./buildpkg.sh <package>.
	@echo 'Refer to the README for more info.'

clean:
	@sudo rm -rf packages/*/tmp
	@rm -rf artifacts
	@rm -f *.buildinfo *.changes *.deb
	@rm -rf update-status

shellcheck:
	shellcheck --exclude=SC1090,SC1091 \
		$$(find . -type f -name '*.sh')

shfmtcheck:
	! shfmt -d $$(find . -type f -name '*.sh') | grep .

check: shellcheck shfmtcheck
