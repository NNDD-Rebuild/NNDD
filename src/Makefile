.PHONY: build pathcheck with-docker help
.DEFAULT_GOAL=help

build: NNDD.exe ## NNDD.exe をビルドします

pathcheck:
	@if [ -z "$$AIR_HOME" ]; then \
		echo 'AIR_HOMEが設定されてないよ。'; \
		echo '末尾に"/"が付かないように指定してね。'; \
		echo; \
		exit 1; \
	fi

NNDD.exe: pathcheck NNDD.swf
	@if [ ! -f certificate_no_password.pfx ]; then \
		java -jar $$AIR_HOME/lib/adt.jar -certificate -cn SelfSigned 2048-RSA certificate_no_password.pfx ''; \
	fi
	@java -jar $$AIR_HOME/lib/adt.jar -package -tsa none -storetype pkcs12 -keystore certificate_no_password.pfx -storepass '' -target native NNDD.exe NNDD-app.xml NNDD.swf icon32.png icon128.png icon48.png icon16.png CategoryList.json

NNDD.swf: pathcheck
	@$$AIR_HOME/bin/amxmlc NNDD.mxml -source-path ../nicovideo4as/src -include-libraries ../libs/flashlsOSMF.swc ../libs/airhttpd-0.5-mineap-0.1.swc ../libs/NativeApplicationUpdater-0.5.1.swc -warnings=false

with-docker: ## Dockerコンテナを使って NNDD.air をビルドします
	@docker run --rm -it -v $$(cd ../ && pwd):/root/NNDD nndd-builder /bin/sh -c 'cd /root/NNDD/src && make build'

help: ## このヘルプを表示します
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
