pragma solidity ^0.4.15;

import './base.t.sol';
import './db.sol';

contract DBTester {
    TestableManager _manager;
    function bindManager(address manager) {
        _manager = TestableManager(manager);
    }
}

contract BasicDBTest is AuctionTest, AuctionDatabase {
    AuctionDatabase _db;

    function setUp() {
        _db = new AuctionDatabase();

        Auction memory auction;
        auction.creator = 0x123;
        createAuction(auction);

        Auctionlet memory auctionlet;
        auctionlet.auction_id = 1;
        createAuctionlet(auctionlet);
    }
    function testFailNullAccessAuction() {
        Auction memory auction;
        var id = createAuction(auction);
        auctions(id);
    }
    function testFailNullAccessAuctionlet() {
        Auctionlet memory auctionlet;
        var id = createAuctionlet(auctionlet);
        auctionlets(id);
    }
    function testFailAccessZerothAuction() {
        auctions(0);
    }
    function testFailAccessZerothAuctionlet() {
        auctionlets(0);
    }
}

contract AuctionDBTest is AuctionTest {
    DBTester tester;

    function newAuction() returns (uint, uint) {
        return manager.newAuction( seller    // beneficiary
                                 , t1        // selling
                                 , t2        // buying
                                 , 100 * T1  // sell_amount
                                 , 10 * T2   // start_bid
                                 , 1         // min_increase
                                 , 1 years   // ttl
                                 );
    }
    function testDefaultRefund() {
        var (id, base) = newAuction();

        assertEq(manager.getRefundAddress(id), seller);
    }
}
