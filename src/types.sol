pragma solidity ^0.4.15;

import 'ds-token/base.sol';

contract AuctionType {
    struct Auction {
        address creator;
        address beneficiary;
        address refund;
        ERC20 selling;
        ERC20 buying;
        uint start_bid;
        uint min_increase;
        uint min_decrease;
        uint sell_amount;
        uint collected;
        uint collection_limit;
        uint64 ttl;
        uint64 expiration;
        bool reversed;
        uint unsold;
    }
    struct Auctionlet {
        uint     auction_id;
        address  last_bidder;
        uint64   last_bid_time;
        uint     buy_amount;
        uint     sell_amount;
        bool     unclaimed;
        bool     base;
    }
}

contract AuctionFrontendType {
    function bid(uint auctionlet_id, uint bid_how_much, bool reverse) public;
    function claim(uint auctionlet_id) public;
}

contract SplittingAuctionFrontendType {
    function bid(uint auctionlet_id, uint bid_how_much, uint quantity,
                 bool reverse)
        public
        returns (uint new_id, uint split_id);
    function claim(uint auctionlet_id) public;
}
