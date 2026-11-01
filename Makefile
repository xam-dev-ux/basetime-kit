SEPOLIA_RPC_URL := https://sepolia.base.org
DEPLOYER := 0x8F058fE6b568D97f85d517Ac441b52B95722fDDe
BASETIME := 0x4200000000000000000000000000000000000030

.PHONY: install build test test-fork check-keystore check-predeploy \
        deploy-sepolia record-deploy verify-basescan exercise measure

install:
	base-forge install foundry-rs/forge-std --no-git

build:
	base-forge build

test:
	base-forge test --no-match-path "test/fork/*" -vv

test-fork:
	base-forge test --match-path "test/fork/*" --fork-url $(SEPOLIA_RPC_URL) -vv

check-keystore:
	@base-cast wallet address --account speedrun | \
		grep -qi "$(DEPLOYER)" && echo "keystore OK" || \
		(echo "KEYSTORE MISMATCH - expected $(DEPLOYER)" && exit 1)

check-predeploy:
	@echo "millisPart:"
	@base-cast call $(BASETIME) "timestampMillisPart()(uint16)" --rpc-url $(SEPOLIA_RPC_URL)
	@echo "timestampMs:"
	@base-cast call $(BASETIME) "timestampMs()(uint256)" --rpc-url $(SEPOLIA_RPC_URL)

deploy-sepolia: check-keystore check-predeploy
	base-forge script script/Deploy.s.sol \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account speedrun \
		--broadcast \
		--verify \
		-vv
	$(MAKE) record-deploy
	$(MAKE) verify-basescan

record-deploy:
	bash script/record-deploy.sh

# --verify alone submits to Sourcify; BaseScan needs an explicit etherscan verifier.
# Requires BASESCAN_API_KEY in the environment (source .env).
verify-basescan:
	@test -n "$$BASESCAN_API_KEY" || (echo "BASESCAN_API_KEY not set (source .env)" && exit 1)
	ETHERSCAN_API_KEY=$$BASESCAN_API_KEY base-forge verify-contract $$(jq -r .oracle .deployments/sepolia.json) \
		src/BlockRateOracle.sol:BlockRateOracle --chain 84532 --verifier etherscan --watch
	ETHERSCAN_API_KEY=$$BASESCAN_API_KEY base-forge verify-contract $$(jq -r .demo .deployments/sepolia.json) \
		src/DenimDemo.sol:DenimDemo --chain 84532 --verifier etherscan --watch

exercise: check-keystore
	bash script/exercise.sh

measure:
	bash script/measure.sh
