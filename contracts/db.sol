import 'types.sol';
import 'util.sol';
import 'erc20/erc20.sol';

// CRUD database for auctions and auctionlets. Create, Read(only) and
// Delete are done with methods here. For gas reasons, Update is done by
// explicitly modifiying storage (i.e. accessing _auctions / _auctionlets).
contract AuctionDatabase is AuctionType {
    mapping(uint => Auction) _auctions;
    uint _last_auction_id;

    mapping(uint => Auctionlet) _auctionlets;
    uint _last_auctionlet_id;

    function createAuctionlet(Auctionlet a)
        internal
        returns (uint id)
    {
        id = ++_last_auctionlet_id;
        _auctionlets[id] = a;
    }
    function createAuction(Auction A)
        internal
        returns (uint id)
    {
        id = ++_last_auction_id;
        _auctions[id] = A;
    }
    function readAuctionlet(uint auctionlet_id)
        internal
        constant
        returns (Auctionlet memory a)
    {
        a = _auctionlets[auctionlet_id];
    }
    function readAuction(uint auction_id)
        internal
        constant
        returns (Auction memory A)
    {
        A = _auctions[auction_id];
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

contract AuctionDatabaseUser is AuctionDatabase, TimeUser {
    function newAuctionlet(uint auction_id, uint bid,
                           uint quantity, address last_bidder, bool base)
        internal
        returns (uint auctionlet_id)
    {
        Auctionlet memory auctionlet;
        auctionlet.auction_id = auction_id;
        auctionlet.unclaimed = true;
        auctionlet.last_bidder = last_bidder;
        auctionlet.base = base;
        auctionlet.last_bid_time = getTime();

        auctionlet_id = createAuctionlet(auctionlet);

        setLastBid(auctionlet_id, bid, quantity);
    }

    function getAuctionInfo(uint auction_id)
        constant
        returns ( address creator
                , ERC20 selling
                , ERC20 buying
                , uint start_bid
                , uint min_increase
                , uint min_decrease
                , uint sell_amount
                , uint duration
                , bool reversed
                , uint unsold
                )
    {
      var a = _auctions[auction_id];
      return (a.creator, a.selling, a.buying, a.start_bid, a.min_increase,
              a.min_decrease, a.sell_amount, a.duration, a.reversed, a.unsold);
    }

    function getAuctionletInfo(uint auctionlet_id)
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
        var a = _auctionlets[auctionlet_id];
        return (a.auction_id, a.last_bidder, a.last_bid_time,
                a.buy_amount, a.sell_amount, a.unclaimed, a.base);
    }

    function setReversed(uint auction_id, bool reversed)
        internal
    {
        _auctions[auction_id].reversed = reversed;
    }
    // check if an auction is reversed
    function isReversed(uint auction_id)
        constant
        returns (bool reversed)
    {
        return _auctions[auction_id].reversed;
    }
    // check if an auctionlet is expired
    // N.B. base auctionlets cannot expire
    function isExpired(uint auctionlet_id)
        constant
        returns (bool expired)
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];
        expired = ((getTime() - a.last_bid_time) > A.duration) && !a.base;
    }
    function getRefundAddress(uint auction_id)
        returns (address)
    {
        return _auctions[auction_id].refund;
    }
    function setRefundAddress(uint auction_id, address refund)
        internal
    {
        var A = _auctions[auction_id];
        A.refund = refund;
    }
    // Auctionlet bid update logic.
    function newBid(uint auctionlet_id, address bidder, uint bid_how_much)
        internal
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        var quantity = A.reversed ? a.buy_amount : a.sell_amount;

        setLastBid(auctionlet_id, bid_how_much, quantity);
        a.last_bidder = bidder;
    }
    function getLastBid(uint auctionlet_id)
        internal
        constant
        returns (uint prev_bid, uint prev_quantity)
    {
        var a = readAuctionlet(auctionlet_id);
        var A = readAuction(a.auction_id);

        if (A.reversed) {
            prev_bid = a.sell_amount;
            prev_quantity = a.buy_amount;
        } else {
            prev_bid = a.buy_amount;
            prev_quantity = a.sell_amount;
        }
    }
    function setLastBid(uint auctionlet_id, uint bid, uint quantity)
        internal
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        if (A.reversed) {
            a.sell_amount = bid;
            a.buy_amount = quantity;
        } else {
            a.sell_amount = quantity;
            a.buy_amount = bid;
        }
    }
    function newGenericAuction( address creator
                              , address[] beneficiaries
                              , uint[] payouts
                              , ERC20 selling
                              , ERC20 buying
                              , uint sell_amount
                              , uint start_bid
                              , uint min_increase
                              , uint min_decrease
                              , uint duration
                              , uint collection_limit
                              , bool reversed
                              )
        internal
        returns (uint auction_id, uint base_id)
    {
        Auction memory A;
        A.creator = creator;
        A.beneficiaries = beneficiaries;
        A.payouts = payouts;
        A.refund = beneficiaries[0];
        A.selling = selling;
        A.buying = buying;
        A.sell_amount = sell_amount;
        A.start_bid = start_bid;
        A.min_increase = min_increase;
        A.min_decrease = min_decrease;
        A.duration = duration;
        A.collection_limit = collection_limit;
        A.unsold = sell_amount;

        auction_id = createAuction(A);

        // create the base auctionlet
        base_id = newAuctionlet({ auction_id:  auction_id
                                , bid:         A.start_bid
                                , quantity:    A.sell_amount
                                , last_bidder: A.beneficiaries[0]
                                , base:        true
                                });

        // set reversed after newAuctionlet because of reverse specific logic
        setReversed(auction_id, reversed);
        // TODO: this is a code smell. There may be a way around this by
        // rethinking the reversed logic throughout - possibly renaming
        // a.sell_amount / a.buy_amount
    }
}
