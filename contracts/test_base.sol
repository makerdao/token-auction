import 'dapple/test.sol';
import 'erc20/erc20.sol';
import 'splitting_auction.sol';

contract TestableManager is SplittingAuctionManager {
    uint public debug_timestamp;

    function getTime() public constant returns (uint) {
        return debug_timestamp;
    }
    function setTime(uint timestamp) {
        debug_timestamp = timestamp;
    }
    function getCollectMax(uint auction_id) returns (uint) {
        return _auctions[auction_id].collection_limit;
    }
    function isReversed(uint auction_id) returns (bool) {
        return _auctions[auction_id].reversed;
    }
    function getAuction(uint id) constant
        returns (address, ERC20, ERC20, uint, uint, uint, uint)
    {
        Auction a = _auctions[id];
        return (a.beneficiaries[0], a.selling, a.buying,
                a.sell_amount, a.start_bid, a.min_increase, a.expiration);
    }
    function getAuctionlet(uint id) constant
        returns (uint, address, uint, uint)
    {
        Auctionlet a = _auctionlets[id];
        return (a.auction_id, a.last_bidder, a.buy_amount, a.sell_amount);
    }
}

contract AuctionTester is Tester {
    TestableManager manager;
    function bindManager(TestableManager _manager) {
        _target(_manager);
        manager = TestableManager(_t);
    }
    function doApprove(address spender, uint value, ERC20 token) {
        token.approve(spender, value);
    }
    function doBid(uint auctionlet_id, uint bid_how_much)
    {
        return manager.bid(auctionlet_id, bid_how_much);
    }
    function doBid(uint auctionlet_id, uint bid_how_much, uint sell_amount)
        returns (uint, uint)
    {
        return manager.bid(auctionlet_id, bid_how_much, sell_amount);
    }
    function doClaim(uint id) {
        return manager.claim(id);
    }
    function doReclaim(uint id) {
        return manager.reclaim(id);
    }
}
