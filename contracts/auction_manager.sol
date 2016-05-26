import 'erc20/erc20.sol';
import 'assertive.sol';

contract TimeUser {
    // Using this allows override of the block timestamp in tests
    function getTime() public constant returns (uint) {
        return block.timestamp;
    }
}

contract AuctionUser is Assertive, TimeUser {
    struct Auction {
        address beneficiary;
        ERC20 selling;
        ERC20 buying;
        uint start_bid;
        uint min_increase;
        uint min_decrease;
        uint sell_amount;
        uint collected;
        uint COLLECT_MAX;
        uint expiration;
        bool reversed;
    }
    struct Auctionlet {
        uint     auction_id;
        address  last_bidder;
        uint     buy_amount;
        uint     sell_amount;
        bool     unclaimed;
    }
    mapping(uint => Auction) _auctions;
    uint _last_auction_id;

    mapping(uint => Auctionlet) _auctionlets;
    uint _last_auctionlet_id;

    // bid on a specifc auctionlet
    function bid(uint auctionlet_id, uint bid_how_much) {
        _assertBiddable(auctionlet_id, bid_how_much);
        _doBid(auctionlet_id, msg.sender, bid_how_much);
    }
    // Parties to an auction can claim their take. The auction creator
    // (the beneficiary) can claim across an entire auction. Individual
    // auctionlet high bidders must claim per auctionlet.
    function claim(uint auctionlet_id) {
        _assertClaimable(auctionlet_id);
        _doClaim(auctionlet_id);
    }
    // Check whether an auctionlet is eligible for bidding on
    function _assertBiddable(uint auctionlet_id, uint bid_how_much) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        assert(a.auction_id > 0);  // test for deleted auction
        assert(auctionlet_id > 0);  // test for deleted auctionlet

        var expired = A.expiration <= getTime();
        assert(!expired);

        if (A.reversed) {
            //@log check if reverse biddable
            assert(bid_how_much <= (a.sell_amount - A.min_decrease));
        } else {
            //@log check if forward biddable
            assert(bid_how_much >= (a.buy_amount + A.min_increase));
        }
    }
    function _doBid(uint auctionlet_id, address bidder, uint bid_how_much)
        internal
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        // new bidder pays off the old bidder directly. For the first
        // bid this is the seller, so they receive their minimum bid.
        var bid_paid_off = A.buying.transferFrom(bidder, a.last_bidder, a.buy_amount);
        assert(bid_paid_off);

        if (!A.reversed) {
            // excess buy token is sent directly from bidder to beneficiary
            var sent_excess_buy = A.buying.transferFrom(bidder, A.beneficiary, bid_how_much - a.buy_amount);
            assert(sent_excess_buy);
        } else {
            // excess sell token is sent from auction escrow to the beneficiary
            var sent_excess_sell = A.selling.transfer(A.beneficiary, a.sell_amount - bid_how_much);
            assert(sent_excess_sell);
        }

        // update the bid quantities - new bidder, new bid, same quantity
        _updateBid(auctionlet_id, bidder, bid_how_much);
    }
    function _updateBid(uint auctionlet_id, address bidder, uint bid_how_much) {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        if (!A.reversed) {
            a.buy_amount = bid_how_much;
        } else {
            a.sell_amount = bid_how_much;
        }

        a.last_bidder = bidder;
    }
    function _assertClaimable(uint auctionlet_id) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        var expired = A.expiration <= getTime();
        assert(expired);

        assert(a.unclaimed);
    }
    // claim the proceedings from an auction for the highest bidder
    function _doClaim(uint auctionlet_id) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        var settled = A.selling.transfer(a.last_bidder, a.sell_amount);
        assert(settled);

        a.unclaimed = false;
        delete _auctionlets[auctionlet_id];
    }
    function _getLastBid(Auctionlet a)
        internal constant
        returns (uint prev_bid, uint prev_quantity)
    {
        var A = _auctions[a.auction_id];

        if (A.reversed) {
            prev_bid = a.sell_amount;
            prev_quantity = a.buy_amount;
        } else {
            prev_bid = a.buy_amount;
            prev_quantity = a.sell_amount;
        }
    }
    function _setLastBid(Auctionlet a, uint bid, uint quantity) internal {
        var A = _auctions[a.auction_id];

        if (A.reversed) {
            a.sell_amount = bid;
            a.buy_amount = quantity;
        } else {
            a.sell_amount = quantity;
            a.buy_amount = bid;
        }
    }
}

contract AuctionManager is AuctionUser {
    uint constant INFINITY = 2 ** 256 - 1;
    // Create a new auction, with specific parameters.
    // Bidding is done through the auctions associated auctionlets,
    // of which there is one initially.
    function newAuction( address beneficiary
                        , ERC20 selling
                        , ERC20 buying
                        , uint sell_amount
                        , uint start_bid
                        , uint min_increase
                        , uint duration
                        )
        returns (uint auction_id, uint base_id)
    {
        (auction_id, base_id) = newTwoWayAuction({beneficiary: beneficiary,
                                                  selling: selling,
                                                  buying: buying,
                                                  sell_amount: sell_amount,
                                                  start_bid: start_bid,
                                                  min_increase: min_increase,
                                                  min_decrease: 0,
                                                  duration: duration,
                                                  COLLECT_MAX: INFINITY
                                                });
    }
    function newReverseAuction( address beneficiary
                              , ERC20 selling
                              , ERC20 buying
                              , uint max_sell_amount
                              , uint buy_amount
                              , uint min_decrease
                              , uint duration
                              )
        returns (uint auction_id, uint base_id)
    {
        // the Reverse Auction is the limit of the two way auction
        // where the maximum collected buying token is zero.
        (auction_id, base_id) = newTwoWayAuction({beneficiary: beneficiary,
                                                  selling: selling,
                                                  buying: buying,
                                                  sell_amount: max_sell_amount,
                                                  start_bid: buy_amount,
                                                  min_increase: 0,
                                                  min_decrease: min_decrease,
                                                  duration: duration,
                                                  COLLECT_MAX: 0
                                                });
        Auction A = _auctions[auction_id];
        A.reversed = true;
    }
    function newTwoWayAuction( address beneficiary
                             , ERC20 selling
                             , ERC20 buying
                             , uint sell_amount
                             , uint start_bid
                             , uint min_increase
                             , uint min_decrease
                             , uint duration
                             , uint COLLECT_MAX
                             )
        returns (uint, uint)
    {
        Auction memory A;
        A.beneficiary = beneficiary;
        A.selling = selling;
        A.buying = buying;
        A.sell_amount = sell_amount;
        A.start_bid = start_bid;
        A.min_increase = min_increase;
        A.min_decrease = min_decrease;
        A.expiration = getTime() + duration;
        A.COLLECT_MAX = COLLECT_MAX;

        //@log new auction: receiving `uint sell_amount` from `address beneficiary`
        var received_lot = selling.transferFrom(beneficiary, this, sell_amount);
        assert(received_lot);

        _auctions[++_last_auction_id] = A;

        // create the base auctionlet
        var base_id = newAuctionlet({auction_id: _last_auction_id,
                                     bid:         start_bid,
                                     quantity:    sell_amount,
                                     last_bidder: A.beneficiary
                                   });

        return (_last_auction_id, base_id);
    }
    function newAuctionlet(uint auction_id, uint bid,
                           uint quantity, address last_bidder)
        internal returns (uint)
    {
        Auctionlet memory auctionlet;
        auctionlet.auction_id = auction_id;
        auctionlet.unclaimed = true;
        auctionlet.last_bidder = last_bidder;

        _setLastBid(auctionlet, bid, quantity);

        _auctionlets[++_last_auctionlet_id] = auctionlet;

        return _last_auctionlet_id;
    }
    function getAuction(uint id) constant
        returns (address, ERC20, ERC20, uint, uint, uint, uint)
    {
        Auction a = _auctions[id];
        return (a.beneficiary, a.selling, a.buying,
                a.sell_amount, a.start_bid, a.min_increase, a.expiration);
    }
    function getAuctionlet(uint id) constant
        returns (uint, address, uint, uint)
    {
        Auctionlet a = _auctionlets[id];
        return (a.auction_id, a.last_bidder, a.buy_amount, a.sell_amount);
    }
}
