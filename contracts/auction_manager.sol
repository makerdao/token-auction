import 'erc20/erc20.sol';
import 'assertive.sol';

contract TimeUser {
    // Using this allows override of the block timestamp in tests
    function getTime() public constant returns (uint) {
        return block.timestamp;
    }
}
contract MathUser {
    function flat(uint x, uint y) internal returns (uint) {
        if (x > y) return x - y;
        else return 0;
    }
    function cumsum(uint[] array) internal returns (uint[]) {
        uint[] memory out = new uint[](array.length);
        out[0] = array[0];
        for (uint i = 1; i < array.length; i++) {
            out[i] = array[i] + out[i - 1];
        }
        return out;
    }
    function sum(uint[] array) internal returns (uint total) {
        total = 0;
        for (uint i = 0; i < array.length; i++) {
            total += array[i];
        }
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
        uint[] payouts;
        ERC20 selling;
        ERC20 buying;
        uint start_bid;
        uint min_increase;
        uint min_decrease;
        uint sell_amount;
        uint collected;
        uint collection_limit;
        uint duration;
        bool reversed;
        uint unsold;
    }
    struct Auctionlet {
        uint     auction_id;
        address  last_bidder;
        uint     last_bid_time;
        uint     buy_amount;
        uint     sell_amount;
        bool     unclaimed;
        bool     base;
    }
}

contract TransferUser is Assertive, AuctionTypes, MathUser {
    function takeFundsIntoEscrow(Auction A) internal {
        assert(A.selling.transferFrom(A.creator, this, A.sell_amount));
    }
    function payOffLastBidder(Auction A, Auctionlet a, address bidder) internal {
        assert(A.buying.transferFrom(bidder, a.last_bidder, a.buy_amount));
    }
    function settleExcessBuy(Auction A, address bidder, uint excess_buy) internal {
        if (A.beneficiaries.length == 1) {
            assert(A.buying.transferFrom(bidder, A.beneficiaries[0], excess_buy));
            return;
        }

        var prev_collected = A.collected - excess_buy;

        var limits = cumsum(A.payouts);

        for (uint i = 0; i < limits.length; i++) {
            var prev_limit = (i == 0) ? 0 : limits[i - 1];
            if (prev_limit > A.collected) break;

            var limit = limits[i];
            if (limit < prev_collected) continue;

            var payout = excess_buy
                       - flat(prev_limit, prev_collected)
                       - flat(A.collected, limit);

            assert(A.buying.transferFrom(bidder, A.beneficiaries[i], payout));
        }
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

contract AuctionDatabase is AuctionTypes, TimeUser {
    mapping(uint => Auction) _auctions;
    uint _last_auction_id;

    mapping(uint => Auctionlet) _auctionlets;
    uint _last_auctionlet_id;

    function createAuctionlet(Auctionlet a) internal returns (uint id) {
        id = ++_last_auctionlet_id;
        _auctionlets[id] = a;
    }
    function createAuction(Auction A) internal returns (uint id) {
        id = ++_last_auction_id;
        _auctions[id] = A;
    }
    function setReversed(uint auction_id, bool reversed) internal {
        _auctions[auction_id].reversed = reversed;
    }
    // check if an auction is reversed
    function isReversed(uint auction_id) constant returns (bool reversed) {
        return _auctions[auction_id].reversed;
    }
    // check if an auctionlet is expired
    function isExpired(uint auctionlet_id) constant returns (bool expired) {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];
        expired = (getTime() - a.last_bid_time) > A.duration;
    }
}

contract AuctionUser is EventfulAuction
                      , AuctionDatabase
                      , TransferUser
{
    function newAuctionlet(uint auction_id, uint bid,
                           uint quantity, address last_bidder, bool base)
        internal returns (uint auctionlet_id)
    {
        Auctionlet memory auctionlet;
        auctionlet.auction_id = auction_id;
        auctionlet.unclaimed = true;
        auctionlet.last_bidder = last_bidder;
        auctionlet.base = base;
        auctionlet.last_bid_time = getTime();

        auctionlet_id = createAuctionlet(auctionlet);

        _setLastBid(auctionlet_id, bid, quantity);
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
    // Check whether an auctionlet is eligible for bidding on
    function _assertBiddable(uint auctionlet_id, uint bid_how_much) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        assert(a.auction_id > 0);  // test for deleted auction
        assert(auctionlet_id > 0);  // test for deleted auctionlet

        assert(a.base || !isExpired(auctionlet_id));

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
        _newBid(auctionlet_id, bidder, bid_how_much);
        a.last_bid_time = getTime();
    }
    // Auctionlet bid update logic.
    function _newBid(uint auctionlet_id, address bidder, uint bid_how_much) {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        var quantity = A.reversed ? a.buy_amount : a.sell_amount;

        _setLastBid(auctionlet_id, bid_how_much, quantity);
        a.last_bidder = bidder;
    }
    // Check whether an auctionlet can be claimed.
    function _assertClaimable(uint auctionlet_id) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        assert(isExpired(auctionlet_id));

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
    function _getLastBid(uint auctionlet_id)
        internal constant
        returns (uint prev_bid, uint prev_quantity)
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        if (A.reversed) {
            prev_bid = a.sell_amount;
            prev_quantity = a.buy_amount;
        } else {
            prev_bid = a.buy_amount;
            prev_quantity = a.sell_amount;
        }
    }
    function _setLastBid(uint auctionlet_id, uint bid, uint quantity)
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
        var (beneficiaries, payouts) = makeSinglePayout(beneficiary, INFINITY);

        (auction_id, base_id) = _newTwoWayAuction({creator: msg.sender,
                                                   beneficiaries: beneficiaries,
                                                   payouts: payouts,
                                                   selling: selling,
                                                   buying: buying,
                                                   sell_amount: sell_amount,
                                                   start_bid: start_bid,
                                                   min_increase: min_increase,
                                                   min_decrease: 0,
                                                   duration: duration,
                                                   collection_limit: INFINITY,
                                                   reversed: false
                                                 });
    }
    function newAuction( address[] beneficiaries
                       , uint[] payouts
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
                                                   payouts: payouts,
                                                   selling: selling,
                                                   buying: buying,
                                                   sell_amount: sell_amount,
                                                   start_bid: start_bid,
                                                   min_increase: min_increase,
                                                   min_decrease: 0,
                                                   duration: duration,
                                                   collection_limit: INFINITY,
                                                   reversed: false
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
        var (beneficiaries, payouts) = makeSinglePayout(beneficiary, 0);

        // the Reverse Auction is the limit of the two way auction
        // where the maximum collected buying token is zero.
        (auction_id, base_id) = _newTwoWayAuction({creator: msg.sender,
                                                   beneficiaries: beneficiaries,
                                                   payouts: payouts,
                                                   selling: selling,
                                                   buying: buying,
                                                   sell_amount: max_sell_amount,
                                                   start_bid: buy_amount,
                                                   min_increase: 0,
                                                   min_decrease: min_decrease,
                                                   duration: duration,
                                                   collection_limit: 0,
                                                   reversed: true
                                                 });
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
        var (beneficiaries, payouts) = makeSinglePayout(beneficiary, collection_limit);

        return _newTwoWayAuction({creator: msg.sender,
                                  beneficiaries: beneficiaries,
                                  payouts: payouts,
                                  selling: selling,
                                  buying: buying,
                                  sell_amount: sell_amount,
                                  start_bid: start_bid,
                                  min_increase: min_increase,
                                  min_decrease: min_decrease,
                                  duration: duration,
                                  collection_limit: collection_limit,
                                  reversed: false
                                  });
    }
    function newTwoWayAuction( address[] beneficiaries
                             , uint[] payouts
                             , ERC20 selling
                             , ERC20 buying
                             , uint sell_amount
                             , uint start_bid
                             , uint min_increase
                             , uint min_decrease
                             , uint duration
                             )
        returns (uint, uint)
    {
        var collection_limit = sum(payouts);
        return _newTwoWayAuction({creator: msg.sender,
                                  beneficiaries: beneficiaries,
                                  payouts: payouts,
                                  selling: selling,
                                  buying: buying,
                                  sell_amount: sell_amount,
                                  start_bid: start_bid,
                                  min_increase: min_increase,
                                  min_decrease: min_decrease,
                                  duration: duration,
                                  collection_limit: collection_limit,
                                  reversed: false
                                  });
    }
    function _checkPayouts(Auction A) internal {
        assert(A.beneficiaries.length == A.payouts.length);
        if (!A.reversed) assert(A.payouts[0] >= A.start_bid);
        assert(sum(A.payouts) == A.collection_limit);
    }
    function makeSinglePayout(address beneficiary, uint collection_limit)
        internal
        returns (address[], uint[])
    {
        address[] memory beneficiaries = new address[](1);
        uint[] memory payouts = new uint[](1);

        beneficiaries[0] = beneficiary;
        payouts[0] = collection_limit;

        return (beneficiaries, payouts);
    }
    function _newTwoWayAuction( address creator
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
        A.reversed = reversed;
        // TODO: this is a code smell. There may be a way around this by
        // rethinking the reversed logic throughout - possibly renaming
        // a.sell_amount / a.buy_amount

        _checkPayouts(A);
        takeFundsIntoEscrow(A);

        NewAuction(auction_id, base_id);
    }
}
