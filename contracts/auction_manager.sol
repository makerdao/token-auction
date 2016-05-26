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
        address creator;
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
        uint sold;
    }
    struct Auctionlet {
        uint     auction_id;
        address  last_bidder;
        uint     buy_amount;
        uint     sell_amount;
        bool     unclaimed;
        bool     bid;
    }
    mapping(uint => Auction) _auctions;
    uint _last_auction_id;

    mapping(uint => Auctionlet) _auctionlets;
    uint _last_auctionlet_id;

    // Place a new bid on a specific auctionlet.
    function bid(uint auctionlet_id, uint bid_how_much) {
        _assertBiddable(auctionlet_id, bid_how_much);
        _doBid(auctionlet_id, msg.sender, bid_how_much);
    }
    // Allow parties to an auction to claim their take.
    // If the auction has expired, individual auctionlet high bidders
    // can claim their winnings.
    function claim(uint auctionlet_id) {
        _assertClaimable(auctionlet_id);
        _doClaim(auctionlet_id);
    }
    // Starting an auction takes funds from the beneficiary to keep in
    // escrow. If there are any funds remaining after expiry, e.g. if
    // there were no bids or if only a portion of the lot was bid for,
    // the seller can reclaim them.
    function reclaim(uint auction_id) {
        var A = _auctions[auction_id];
        var expired = A.expiration <= getTime();
        assert(expired);

        A.selling.transfer(A.beneficiary, A.sell_amount - A.sold);
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
    // Auctionlet bid logic, including transfers.
    function _doBid(uint auctionlet_id, address bidder, uint bid_how_much)
        internal
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        // new bidder pays off the old bidder directly. For the first
        // bid this is the seller, so they receive their minimum bid.
        assert(A.buying.transferFrom(bidder, a.last_bidder, a.buy_amount));

        // if the auctionlet has not been bid on before we need to
        // do some extra accounting
        if (!a.bid) {
            A.collected += a.buy_amount;
            A.sold += a.sell_amount;
            a.bid = true;
        }

        if (!A.reversed) {
            var excess_buy = bid_how_much - a.buy_amount;
            A.collected += excess_buy;
        }

        // determine if this bid causes a forward -> reverse transition
        // (only happens in the twoway auction)
        var transition = !A.reversed && (A.collected > A.COLLECT_MAX);

        if (transition) {
            // only take excess from the bidder up to the collect target.
            var bid_over_target = A.collected - A.COLLECT_MAX;
            A.collected = A.COLLECT_MAX;

            assert(A.buying.transferFrom(bidder, A.beneficiary, excess_buy - bid_over_target));

            // over the target, impute how much less they would have been
            // willing to accept, based on their bid price
            var effective_target_bid = (a.sell_amount * A.COLLECT_MAX) / A.sell_amount;
            var reduced_sell_amount = (a.sell_amount * effective_target_bid) / bid_how_much;
            //@log effective target bid: `uint effective_target_bid`
            //@log previous sell_amount: `uint a.sell_amount`
            //@log reduced sell_amount:  `uint reduced_sell_amount`
            a.buy_amount = bid_how_much - bid_over_target;
            bid_how_much = reduced_sell_amount;
            A.reversed = true;
        } else if (!A.reversed) {
            // excess buy token is sent directly from bidder to beneficiary
            assert(A.buying.transferFrom(bidder, A.beneficiary, excess_buy));
        } else {
            // excess sell token is sent from auction escrow to the beneficiary
            assert(A.selling.transfer(A.beneficiary, a.sell_amount - bid_how_much));
        }

        // update the bid quantities - new bidder, new bid, same quantity
        _updateBid(auctionlet_id, bidder, bid_how_much);
    }
    // Auctionlet bid update logic.
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
    // Check whether an auctionlet can be claimed.
    function _assertClaimable(uint auctionlet_id) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        var expired = A.expiration <= getTime();
        assert(expired);

        assert(a.unclaimed);
    }
    // Auctionlet claim logic, including transfers.
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
    // Create a new forward auction.
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
        (auction_id, base_id) = _newTwoWayAuction({creator: msg.sender,
                                                   beneficiary: beneficiary,
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
    // Create a new reverse auction
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
        (auction_id, base_id) = _newTwoWayAuction({creator: msg.sender,
                                                   beneficiary: beneficiary,
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
    // Create a new two-way auction.
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
        return _newTwoWayAuction({creator: msg.sender,
                                  beneficiary: beneficiary,
                                  selling: selling,
                                  buying: buying,
                                  sell_amount: sell_amount,
                                  start_bid: start_bid,
                                  min_increase: min_increase,
                                  min_decrease: min_decrease,
                                  duration: duration,
                                  COLLECT_MAX: COLLECT_MAX
                                  });
    }
    function _newTwoWayAuction( address creator
                              , address beneficiary
                              , ERC20 selling
                              , ERC20 buying
                              , uint sell_amount
                              , uint start_bid
                              , uint min_increase
                              , uint min_decrease
                              , uint duration
                              , uint COLLECT_MAX
                              )
        internal
        returns (uint, uint)
    {
        Auction memory A;
        A.creator = creator;
        A.beneficiary = beneficiary;
        A.selling = selling;
        A.buying = buying;
        A.sell_amount = sell_amount;
        A.start_bid = start_bid;
        A.min_increase = min_increase;
        A.min_decrease = min_decrease;
        A.expiration = getTime() + duration;
        A.COLLECT_MAX = COLLECT_MAX;

        //@log new auction: receiving `uint sell_amount` from `address creator`
        assert(selling.transferFrom(A.creator, this, A.sell_amount));

        _auctions[++_last_auction_id] = A;

        // create the base auctionlet
        var base_id = newAuctionlet({auction_id: _last_auction_id,
                                     bid:         A.start_bid,
                                     quantity:    A.sell_amount,
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
