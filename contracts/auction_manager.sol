import 'erc20/erc20.sol';
import 'assertive.sol';

contract AuctionManager is Assertive {
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
        uint claimed;
        uint expiration;
        bool reversed;
        uint excess_claimable;
    }
    struct Auctionlet {
        uint     auction_id;
        address  last_bidder;
        uint     last_bid;
        uint     quantity;
        bool     unclaimed;
    }

    uint constant INFINITY = 2 ** 256 - 1;

    mapping(uint => Auction) _auctions;
    uint _last_auction_id;

    mapping(uint => Auctionlet) _auctionlets;
    uint _last_auctionlet_id;

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
        // make an empty bid to trigger the reversal
        // TODO: split out the reversal logic into a function
        _doBid(base_id, address(0x00), 0);
        Auctionlet a = _auctionlets[base_id];
        a.quantity = max_sell_amount;
        a.last_bid = buy_amount;
        a.last_bidder = beneficiary;
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
        Auction memory a;
        a.beneficiary = beneficiary;
        a.selling = selling;
        a.buying = buying;
        a.sell_amount = sell_amount;
        a.start_bid = start_bid;
        a.min_increase = min_increase;
        a.min_decrease = min_decrease;
        a.expiration = getTime() + duration;
        a.COLLECT_MAX = COLLECT_MAX;

        var received_lot = selling.transferFrom(beneficiary, this, sell_amount);
        assert(received_lot);

        _auctions[++_last_auction_id] = a;

        // create the base auctionlet
        var base_id = newAuctionlet({auction_id: _last_auction_id,
                                     quantity:    sell_amount});

        return (_last_auction_id, base_id);
    }
    function newAuctionlet(uint auction_id, uint quantity)
        internal returns (uint)
    {
        var A = _auctions[auction_id];

        Auctionlet memory auctionlet;
        auctionlet.auction_id = auction_id;
        auctionlet.unclaimed = true;
        auctionlet.last_bidder = this;

        if (A.reversed) {
            auctionlet.last_bid = quantity;
        } else {
            auctionlet.quantity = quantity;
        }

        _auctionlets[++_last_auctionlet_id] = auctionlet;

        return _last_auctionlet_id;
    }
    // bid on a specifc auctionlet
    function bid(uint auctionlet_id, uint bid_how_much) {
        _assertBiddable(auctionlet_id, bid_how_much);
        _doBid(auctionlet_id, msg.sender, bid_how_much);
    }
    // Parties to an auction can claim their take. The auction creator
    // (the beneficiary) can claim across an entire auction. Individual
    // auctionlet high bidders must claim per auctionlet.
    function claim(uint id) {
        if (msg.sender == _auctions[id].beneficiary) {
            _doClaimSeller(id);
        } else {
            _doClaimBidder(id, msg.sender);
        }
    }
    // Check whether an auctionlet is eligible for bidding on
    function _assertBiddable(uint auctionlet_id, uint bid_how_much) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        assert(a.auction_id > 0);  // test for deleted auctionlet

        var expired = A.expiration <= getTime();
        assert(!expired);

        if (A.reversed) {
            //@log check if reverse biddable
            _assertReverseBiddable(auctionlet_id, bid_how_much);
        } else {
            //@log check if forward biddable
            _assertForwardBiddable(auctionlet_id, bid_how_much);
        }
    }
    function _assertForwardBiddable(uint auctionlet_id, uint bid_how_much) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        assert(bid_how_much >= A.start_bid);
        assert(bid_how_much >= (a.last_bid + A.min_increase));
    }
    function _assertReverseBiddable(uint auctionlet_id, uint bid_how_much) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];
        //@log bid how much: `uint bid_how_much`
        //@log quantity:     `uint a.quantity`
        //@log last bid:     `uint a.last_bid`
        //@log min decrease: `uint A.min_decrease`
        assert(bid_how_much <= a.quantity - A.min_decrease);
    }
    function _doBid(uint auctionlet_id, address bidder, uint bid_how_much)
        internal
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        uint receive_amount;
        if (A.reversed) {
            receive_amount = a.last_bid;
        } else {
            receive_amount = bid_how_much;
        }

        //@log receive `uint receive_amount` from `address bidder`
        var received_bid = A.buying.transferFrom(bidder, this, receive_amount);
        assert(received_bid);

        //@log return  `uint a.last_bid` to   `address a.last_bidder`
        var returned_bid = A.buying.transfer(a.last_bidder, a.last_bid);
        assert(returned_bid);

        A.collected += receive_amount;
        A.collected -= a.last_bid;

        a.last_bidder = bidder;

        if (A.reversed) {
            A.excess_claimable += a.quantity - bid_how_much;
            a.quantity = bid_how_much;
        } else {
            a.last_bid = bid_how_much;
        }

        if (!A.reversed && (A.collected >= A.COLLECT_MAX)) {
            // return excess to bidder
            var excess = A.collected - A.COLLECT_MAX;
            var returned_excess = A.buying.transfer(bidder, excess);
            assert(returned_excess);

            A.collected = A.COLLECT_MAX;
            A.reversed = true;

            a.last_bid = bid_how_much - excess;

            var effective_target_bid = (a.quantity * A.COLLECT_MAX) / A.sell_amount;
            var reduced_quantity = (a.quantity * effective_target_bid) / bid_how_much;
            //@log effective target bid: `uint effective_target_bid`
            //@log previous quantity:    `uint a.quantity`
            //@log reduced quantity:     `uint reduced_quantity`
            a.quantity = reduced_quantity;
        }
    }
    // claim the existing bids from all auctionlets connected to a
    // specific auction
    function _doClaimSeller(uint auction_id) internal {
        var A = _auctions[auction_id];

        //@log collected: `uint A.collected`
        //@log claimed:   `uint A.claimed`
        //@log balance:   `uint A.buying.balanceOf(this)`
        var settled = A.buying.transfer(A.beneficiary, A.collected - A.claimed);
        assert(settled);

        // transfer excess sell token
        if (A.reversed) {
            var settled_excess = A.selling.transfer(A.beneficiary,
                                                    A.excess_claimable);
            assert(settled_excess);
            A.excess_claimable = 0;
        }

        A.claimed = A.collected;
    }
    // claim the proceedings from an auction for the highest bidder
    function _doClaimBidder(uint auctionlet_id, address claimer) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        assert(claimer == a.last_bidder);

        var expired = A.expiration <= getTime();
        assert(expired);

        assert(a.unclaimed);

        var settled = A.selling.transfer(a.last_bidder, a.quantity);
        assert(settled);

        a.unclaimed = false;
        delete _auctionlets[auctionlet_id];
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
        return (a.auction_id, a.last_bidder, a.last_bid, a.quantity);
    }
    function getTime() public constant returns (uint) {
        return block.timestamp;
    }
}
