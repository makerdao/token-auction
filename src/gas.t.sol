pragma solidity ^0.4.15;

import './base.t.sol';


contract ForwardGasTest is AuctionTest {
    uint id;
    uint base;

    modifier pre_create {
        (id, base) = newAuction();
        _;
    }
    modifier pre_bid(uint how_much) {
        bidder1.doBid(base, how_much, false);
        _;
    }
    modifier force_expiry {
        manager.addTime(100 years);
        _;
    }
    function newAuction() public returns (uint, uint) {
        return manager.newAuction(beneficiary1, t1, t2, 100 * T1, 0, 1, 1 hours);
    }
    function testBaseBid()
        public
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 10 * T2, false);
    }
    function testBaseSplit()
        public
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 10 * T2, 50 * T1, false);
    }
    function testSubsequentBid()
        public
        pre_create
        pre_bid(10 * T2)
        logs_gas
    {
        bidder1.doBid(base, 20 * T2, false);
    }
    function testSubsequentSplit()
        public
        pre_create
        pre_bid(10 * T2)
        logs_gas
    {
        bidder1.doBid(base, 20 * T2, 50 * T1, false);
    }
    function testClaim()
        public
        pre_create
        pre_bid(10 * T2)
        force_expiry
        logs_gas
    {
        bidder1.doClaim(id);
    }
    function testNewAuction()
        public
        logs_gas
    {
        manager.newAuction(beneficiary1, t1, t2, 100 * T1, 0, 1, 1 hours);
    }
    function testNewManager()
        public
        logs_gas
    {
        new SplittingAuctionManager();
    }
}

contract ReverseGasTest is AuctionTest {
    uint id;
    uint base;

    modifier pre_create {
        (id, base) = newAuction();
        _;
    }
    modifier pre_bid(uint how_much) {
        bidder1.doBid(base, how_much, true);
        _;
    }
    modifier force_expiry {
        manager.addTime(100 years);
        _;
    }
    function newAuction() public returns (uint, uint) {
        return manager.newReverseAuction(beneficiary1, t1, t2, 100 * T1, 100 * T2, 1, 1 hours);
    }
    function testBaseBid()
        public
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 90 * T1, true);
    }
    function testBaseSplit()
        public
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 10 * T1, 50 * T2, true);
    }
    function testSubsequentBid()
        public
        pre_create
        pre_bid(50 * T1)
        logs_gas
    {
        bidder1.doBid(base, 10 * T1, true);
    }
    function testSubsequentSplit()
        public
        pre_create
        pre_bid(50 * T1)
        logs_gas
    {
        bidder1.doBid(base, 10 * T1, 50 * T2, true);
    }
    function testClaim()
        public
        pre_create
        pre_bid(50 * T1)
        force_expiry
        logs_gas
    {
        bidder1.doClaim(id);
    }
    function testNewAuction()
        public
        logs_gas
    {
        newAuction();
    }
    function testNewManager()
        public
        logs_gas
    {
        new SplittingAuctionManager();
    }
}

contract TwoWayGasTest is AuctionTest {
    uint id;
    uint base;

    modifier pre_create {
        (id, base) = newAuction();
        _;
    }
    modifier pre_bid(uint how_much) {
        bidder1.doBid(base, how_much, false);
        _;
    }
    function newAuction() public returns (uint, uint) {
        return manager.newTwoWayAuction(beneficiary1, t1, t2, 100 * T1, 10 * T2, 1, 1, 1 hours, 50 * T2);

    }
    function testTransitionFromBase()
        public
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 60 * T2, false);
    }
    function testTransitionAfterBid()
        public
        pre_create
        pre_bid(40 * T2)
        logs_gas
    {
        bidder1.doBid(base, 60 * T2, false);
    }
    function testSplitTransitionFromBase()
        public
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 50 * T1, 60 * T2, false);
    }
    function testSplitTransitionAfterBid()
        public
        pre_create
        pre_bid(40 * T2)
        logs_gas
    {
        bidder1.doBid(base, 50 * T1, 60 * T2, false);
    }
}
