export SOLC_FLAGS = --optimize

all:; dapp build
test:; dapp test

deploy:; seth send --new 0x"`cat out/SplittingAuctionManager.bin`" \
"SplittingAuctionManager()"
