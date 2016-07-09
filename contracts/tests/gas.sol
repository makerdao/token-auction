import 'tests/base.sol';


contract ForwardGasTest is AuctionTest {
    uint id;
    uint base;

    modifier pre_create {
        (id, base) = newAuction();
        _
    }
    modifier pre_bid(uint how_much) {
        bidder1.doBid(base, how_much);
        _
    }
    modifier force_expiry {
        manager.addTime(100 years);
        _
    }
    function newAuction() returns (uint, uint) {
        return manager.newAuction(beneficiary1, t1, t2, 100 * T1, 0, 1, 1 hours);
    }
    function testBaseBid()
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 10 * T2);
    }
    function testBaseSplit()
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 10 * T2, 50 * T1);
    }
    function testSubsequentBid()
        pre_create
        pre_bid(10 * T2)
        logs_gas
    {
        bidder1.doBid(base, 20 * T2);
    }
    function testSubsequentSplit()
        pre_create
        pre_bid(10 * T2)
        logs_gas
    {
        bidder1.doBid(base, 20 * T2, 50 * T1);
    }
    function testClaim()
        pre_create
        pre_bid(10 * T2)
        force_expiry
        logs_gas
    {
        bidder1.doClaim(id);
    }
    function testNewAuction()
        logs_gas
    {
        manager.newAuction(beneficiary1, t1, t2, 100 * T1, 0, 1, 1 hours);
    }
    function testNewManager()
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
        _
    }
    modifier pre_bid(uint how_much) {
        bidder1.doBid(base, how_much);
        _
    }
    modifier force_expiry {
        manager.addTime(100 years);
        _
    }
    function newAuction() returns (uint, uint) {
        return manager.newReverseAuction(beneficiary1, t1, t2, 100 * T1, 100 * T2, 1, 1 hours);
    }
    function testBaseBid()
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 90 * T1);
    }
    function testBaseSplit()
        pre_create
        logs_gas
    {
        bidder1.doBid(base, 10 * T1, 50 * T2);
    }
    function testSubsequentBid()
        pre_create
        pre_bid(50 * T1)
        logs_gas
    {
        bidder1.doBid(base, 10 * T1);
    }
    function testSubsequentSplit()
        pre_create
        pre_bid(50 * T1)
        logs_gas
    {
        bidder1.doBid(base, 10 * T1, 50 * T2);
    }
    function testClaim()
        pre_create
        pre_bid(50 * T1)
        force_expiry
        logs_gas
    {
        bidder1.doClaim(id);
    }
    function testNewAuction()
        logs_gas
    {
        newAuction();
    }
    function testNewManager()
        logs_gas
    {
        new SplittingAuctionManager();
    }
}
