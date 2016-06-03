import 'erc20/erc20.sol';
import 'assertive.sol';

contract TimeUser {
    // Using this allows override of the block timestamp in tests
    function getTime() public constant returns (uint) {
        return block.timestamp;
    }
}

contract EventfulAuction {
    event Bid(uint indexed auctionlet_id);
    event AuctionReversal(uint indexed auctionlet_id);
}

contract EventfulManager {
    event NewAuction(uint indexed id, uint base_id);
}

contract AuctionTypes {
    struct Auction {
        address creator;
        address[] beneficiaries;
        uint[] limits;
        ERC20 selling;
        ERC20 buying;
        uint start_bid;
        uint min_increase;
        uint min_decrease;
        uint sell_amount;
        uint collected;
        uint collection_limit;
        uint expiration;
        bool reversed;
        uint unsold;
    }
    struct Auctionlet {
        uint     auction_id;
        address  last_bidder;
        uint     buy_amount;
        uint     sell_amount;
        bool     unclaimed;
        bool     base;
    }
}

contract TransferUser is Assertive, AuctionTypes {
    function takeFundsIntoEscrow(Auction A) internal {
        assert(A.selling.transferFrom(A.creator, this, A.sell_amount));
    }
    function payOffLastBidder(Auction A, Auctionlet a, address bidder) internal {
        assert(A.buying.transferFrom(bidder, a.last_bidder, a.buy_amount));
    }
    function settleExcessBuy(Auction A, address bidder, uint excess_buy) internal {
        assert(A.buying.transferFrom(bidder, A.beneficiaries[0], excess_buy));
    }
    function settleExcessSell(Auction A, uint excess_sell) internal {
        assert(A.selling.transfer(A.beneficiaries[0], excess_sell));
    }
    function settleBidderClaim(Auction A, Auctionlet a) internal {
        assert(A.selling.transfer(a.last_bidder, a.sell_amount));
    }
    function settleReclaim(Auction A) internal {
        assert(A.selling.transfer(A.creator, A.unsold));
    }
}

contract AuctionUser is EventfulAuction
                      , TimeUser
                      , TransferUser
{
    mapping(uint => Auction) _auctions;
    uint _last_auction_id;

    mapping(uint => Auctionlet) _auctionlets;
    uint _last_auctionlet_id;

    function newAuctionlet(uint auction_id, uint bid,
                           uint quantity, address last_bidder, bool base)
        internal returns (uint)
    {
        Auctionlet memory auctionlet;
        auctionlet.auction_id = auction_id;
        auctionlet.unclaimed = true;
        auctionlet.last_bidder = last_bidder;
        auctionlet.base = base;

        _setLastBid(auctionlet, bid, quantity);

        _auctionlets[++_last_auctionlet_id] = auctionlet;

        return _last_auctionlet_id;
    }
    // Place a new bid on a specific auctionlet.
    function bid(uint auctionlet_id, uint bid_how_much) {
        _assertBiddable(auctionlet_id, bid_how_much);
        _doBid(auctionlet_id, msg.sender, bid_how_much);
        Bid(auctionlet_id);
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

        settleReclaim(A);
        A.unsold = 0;
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
            // check if reverse biddable
            assert(bid_how_much <= (a.sell_amount - A.min_decrease));
        } else {
            // check if forward biddable
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
        payOffLastBidder(A, a, bidder);

        // if the auctionlet has not been bid on before we need to
        // do some extra accounting
        if (a.base) {
            A.collected += a.buy_amount;
            A.unsold -= a.sell_amount;
            a.base = false;
        }

        if (!A.reversed) {
            var excess_buy = bid_how_much - a.buy_amount;
            A.collected += excess_buy;
        }

        // determine if this bid causes a forward -> reverse transition
        // (only happens in the twoway auction)
        var transition = !A.reversed && (A.collected > A.collection_limit);

        if (transition) {
            // only take excess from the bidder up to the collect target.
            var bid_over_target = A.collected - A.collection_limit;
            A.collected = A.collection_limit;

            settleExcessBuy(A, bidder, excess_buy - bid_over_target);

            // over the target, impute how much less they would have been
            // willing to accept, based on their bid price
            var effective_target_bid = (a.sell_amount * A.collection_limit) / A.sell_amount;
            var reduced_sell_amount = (a.sell_amount * effective_target_bid) / bid_how_much;
            a.buy_amount = bid_how_much - bid_over_target;
            bid_how_much = reduced_sell_amount;
            A.reversed = true;
            AuctionReversal(a.auction_id);
        } else if (!A.reversed) {
            // excess buy token is sent directly from bidder to beneficiary
            settleExcessBuy(A, bidder, excess_buy);
        } else {
            // excess sell token is sent from auction escrow to the beneficiary
            var excess_sell = a.sell_amount - bid_how_much;
            settleExcessSell(A, excess_sell);
            A.sell_amount -= excess_sell;
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

        settleBidderClaim(A, a);

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

contract AuctionManager is AuctionUser, EventfulManager {
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
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint[] memory limits = new uint[](1);

        (auction_id, base_id) = _newTwoWayAuction({creator: msg.sender,
                                                   beneficiaries: beneficiaries,
                                                   limits: limits,
                                                   selling: selling,
                                                   buying: buying,
                                                   sell_amount: sell_amount,
                                                   start_bid: start_bid,
                                                   min_increase: min_increase,
                                                   min_decrease: 0,
                                                   duration: duration,
                                                   collection_limit: INFINITY
                                                 });
    }
    function newAuction( address[] beneficiaries
                       , uint[] limits
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
                                                   beneficiaries: beneficiaries,
                                                   limits: limits,
                                                   selling: selling,
                                                   buying: buying,
                                                   sell_amount: sell_amount,
                                                   start_bid: start_bid,
                                                   min_increase: min_increase,
                                                   min_decrease: 0,
                                                   duration: duration,
                                                   collection_limit: INFINITY
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
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint[] memory limits = new uint[](1);

        // the Reverse Auction is the limit of the two way auction
        // where the maximum collected buying token is zero.
        (auction_id, base_id) = _newTwoWayAuction({creator: msg.sender,
                                                   beneficiaries: beneficiaries,
                                                   limits: limits,
                                                   selling: selling,
                                                   buying: buying,
                                                   sell_amount: max_sell_amount,
                                                   start_bid: buy_amount,
                                                   min_increase: 0,
                                                   min_decrease: min_decrease,
                                                   duration: duration,
                                                   collection_limit: 0
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
                             , uint collection_limit
                             )
        returns (uint, uint)
    {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint[] memory limits = new uint[](1);

        return _newTwoWayAuction({creator: msg.sender,
                                  beneficiaries: beneficiaries,
                                  limits: limits,
                                  selling: selling,
                                  buying: buying,
                                  sell_amount: sell_amount,
                                  start_bid: start_bid,
                                  min_increase: min_increase,
                                  min_decrease: min_decrease,
                                  duration: duration,
                                  collection_limit: collection_limit
                                  });
    }
    function _newTwoWayAuction( address creator
                              , address[] beneficiaries
                              , uint[] limits
                              , ERC20 selling
                              , ERC20 buying
                              , uint sell_amount
                              , uint start_bid
                              , uint min_increase
                              , uint min_decrease
                              , uint duration
                              , uint collection_limit
                              )
        internal
        returns (uint, uint)
    {
        assert(beneficiaries.length == limits.length);

        Auction memory A;
        A.creator = creator;
        A.beneficiaries = beneficiaries;
        A.limits = limits;
        A.selling = selling;
        A.buying = buying;
        A.sell_amount = sell_amount;
        A.start_bid = start_bid;
        A.min_increase = min_increase;
        A.min_decrease = min_decrease;
        A.expiration = getTime() + duration;
        A.collection_limit = collection_limit;
        A.unsold = sell_amount;

        takeFundsIntoEscrow(A);

        _auctions[++_last_auction_id] = A;

        // create the base auctionlet
        var base_id = newAuctionlet({auction_id: _last_auction_id,
                                     bid:         A.start_bid,
                                     quantity:    A.sell_amount,
                                     last_bidder: A.beneficiaries[0],
                                     base:        true
                                   });

        NewAuction(_last_auction_id, base_id);

        return (_last_auction_id, base_id);
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
