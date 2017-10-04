pragma solidity ^0.4.15;

import './types.sol';
import './util.sol';
import 'ds-token/base.sol';
import 'ds-math/math.sol';

contract AuctionDatabase is Assertive, AuctionType {
    mapping(uint => Auction) private _auctions;
    uint private _last_auction_id;

    mapping(uint => Auctionlet) private _auctionlets;
    uint private _last_auctionlet_id;

    function createAuctionlet(Auctionlet auctionlet)
        internal
        returns (uint id)
    {
        id = ++_last_auctionlet_id;
        _auctionlets[id] = auctionlet;
    }
    function createAuction(Auction auction)
        internal
        returns (uint id)
    {
        id = ++_last_auction_id;
        _auctions[id] = auction;
    }
    function auctionlets(uint id)
        constant
        internal
        returns (Auctionlet storage auctionlet)
    {
        assert(id != 0);
        auctionlet = _auctionlets[id];
        assert(auctionlet.auction_id != 0);
    }
    function auctions(uint id)
        constant
        internal
        returns (Auction storage auction)
    {
        assert(id != 0);
        auction = _auctions[id];
        assert(auction.creator != 0);
    }
    function deleteAuctionlet(uint auctionlet_id)
        internal
    {
        delete _auctionlets[auctionlet_id];
    }
    function deleteAuction(uint auction_id)
        internal
    {
        delete _auctions[auction_id];
    }
}

contract AuctionDatabaseUser is AuctionDatabase, DSMath, TimeUser {
    function newAuctionlet( uint auction_id
                          , uint bid
                          , uint quantity
                          , address last_bidder
                          , bool base
                          )
        internal
        returns (uint auctionlet_id)
    {
        Auctionlet memory auctionlet;
        auctionlet.auction_id = auction_id;
        auctionlet.unclaimed = true;
        auctionlet.last_bidder = last_bidder;
        auctionlet.base = base;

        auctionlet_id = createAuctionlet(auctionlet);

        setLastBid(auctionlet_id, bid, quantity);
    }

    function getAuctionInfo(uint auction_id)
        public
        constant
        returns ( address creator
                , ERC20 selling
                , ERC20 buying
                , uint start_bid
                , uint min_increase
                , uint min_decrease
                , uint sell_amount
                , uint64 ttl
                , bool reversed
                , uint unsold
                )
    {
      var auctionlet = auctions(auction_id);
      return (auctionlet.creator, auctionlet.selling, auctionlet.buying,
              auctionlet.start_bid, auctionlet.min_increase,
              auctionlet.min_decrease, auctionlet.sell_amount, auctionlet.ttl,
              auctionlet.reversed, auctionlet.unsold);
    }

    function getAuctionletInfo(uint auctionlet_id)
        public
        constant
        returns ( uint auction_id
                , address last_bidder
                , uint last_bid_time
                , uint buy_amount
                , uint sell_amount
                , bool unclaimed
                , bool base
                )
    {
        var auctionlet = auctionlets(auctionlet_id);
        return (auctionlet.auction_id, auctionlet.last_bidder,
                auctionlet.last_bid_time, auctionlet.buy_amount,
                auctionlet.sell_amount, auctionlet.unclaimed, auctionlet.base);
    }

    function setReversed(uint auction_id, bool reversed)
        internal
    {
        auctions(auction_id).reversed = reversed;
    }
    // check if an auction is reversed
    function isReversed(uint auction_id)
        public
        constant
        returns (bool reversed)
    {
        return auctions(auction_id).reversed;
    }
    // check if an auctionlet is expired
    // N.B. base auctionlets cannot expire
    function isExpired(uint auctionlet_id)
        public
        constant
        returns (bool expired)
    {
        var auctionlet = auctionlets(auctionlet_id);
        var auction = auctions(auctionlet.auction_id);

        var auctionlet_expired = !auctionlet.base
                && (sub(getTime(), auctionlet.last_bid_time) > auction.ttl);

        var auction_expired = getTime() > auction.expiration;

        expired = auctionlet_expired || auction_expired;
    }
    function getRefundAddress(uint auction_id)
        public
        constant
        returns (address)
    {
        return auctions(auction_id).refund;
    }
    function setRefundAddress(uint auction_id, address refund)
        internal
    {
        var auction = auctions(auction_id);
        auction.refund = refund;
    }
    function setExpiration(uint auction_id, uint64 expiration)
        internal
    {
        var auction = auctions(auction_id);
        auction.expiration = expiration;
    }
    function getLastBid(uint auctionlet_id)
        public
        constant
        returns (uint prev_bid, uint prev_quantity)
    {
        var auctionlet = auctionlets(auctionlet_id);
        var auction = auctions(auctionlet.auction_id);

        if (auction.reversed) {
            prev_bid = auctionlet.sell_amount;
            prev_quantity = auctionlet.buy_amount;
        } else {
            prev_bid = auctionlet.buy_amount;
            prev_quantity = auctionlet.sell_amount;
        }
    }
    function setLastBid(uint auctionlet_id, uint bid, uint quantity)
        internal
    {
        var auctionlet = auctionlets(auctionlet_id);
        var auction = auctions(auctionlet.auction_id);

        if (auction.reversed) {
            auctionlet.sell_amount = bid;
            auctionlet.buy_amount = quantity;
        } else {
            auctionlet.sell_amount = quantity;
            auctionlet.buy_amount = bid;
        }
    }
    function newGenericAuction( address creator
                              , address beneficiary
                              , ERC20 selling
                              , ERC20 buying
                              , uint sell_amount
                              , uint start_bid
                              , uint min_increase
                              , uint min_decrease
                              , uint64 ttl
                              , uint collection_limit
                              , bool reversed
                              )
        internal
        returns (uint auction_id, uint base_id)
    {
        Auction memory auction;
        auction.creator = creator;
        auction.beneficiary = beneficiary;
        auction.refund = beneficiary;
        auction.selling = selling;
        auction.buying = buying;
        auction.sell_amount = sell_amount;
        auction.start_bid = start_bid;
        auction.min_increase = min_increase;
        auction.min_decrease = min_decrease;
        auction.ttl = ttl;
        auction.expiration = uint64(-1);  // 'infinity'
        auction.collection_limit = collection_limit;
        auction.unsold = sell_amount;

        auction_id = createAuction(auction);

        // create the base auctionlet
        base_id = newAuctionlet({ auction_id:  auction_id
                                , bid:         auction.start_bid
                                , quantity:    auction.sell_amount
                                , last_bidder: auction.beneficiary
                                , base:        true
                                });

        // set reversed after newAuctionlet because of reverse specific logic
        setReversed(auction_id, reversed);
        // TODO: this is a code smell. There may be a way around this by
        // rethinking the reversed logic throughout - possibly renaming
        // auctionlet.sell_amount / auctionlet.buy_amount
    }
}
