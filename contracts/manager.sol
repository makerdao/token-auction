import 'erc20/erc20.sol';

import 'events.sol';
import 'types.sol';
import 'user.sol';
import 'util.sol';

contract AuctionFrontend is EventfulAuction, AssertiveAuction, AuctionUser {
    // Place a new bid on a specific auctionlet.
    function bid(uint auctionlet_id, uint bid_how_much) external {
        assertBiddable(auctionlet_id, bid_how_much);
        doBid(auctionlet_id, msg.sender, bid_how_much);
        Bid(auctionlet_id);
    }
    // Allow parties to an auction to claim their take.
    // If the auction has expired, individual auctionlet high bidders
    // can claim their winnings.
    function claim(uint auctionlet_id) external {
        assertClaimable(auctionlet_id);
        doClaim(auctionlet_id);
    }
}

contract SplittingAuctionFrontend is AuctionFrontend {
    // Place a partial bid on an auctionlet, for less than the full lot.
    // This splits the auctionlet into two, bids on one of the new
    // auctionlets and leaves the other to the previous bidder.
    // The new auctionlet ids are returned, corresponding to the new
    // auctionlets owned by (prev_bidder, new_bidder).
    function bid(uint auctionlet_id, uint bid_how_much, uint quantity) external
        returns (uint new_id, uint split_id)
    {
        assertSplittable(auctionlet_id, bid_how_much, quantity);
        (new_id, split_id) = doSplit(auctionlet_id, msg.sender, bid_how_much, quantity);
        Split(auctionlet_id, new_id, split_id);
    }
}

contract AuctionManager is MathUser, AuctionType, AuctionFrontend, EventfulManager {
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
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, INFINITY);

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
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, 0);

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
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, collection_limit);

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
    function _makeSinglePayout(address beneficiary, uint collection_limit)
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
        A.reversed = reversed;
        // TODO: this is a code smell. There may be a way around this by
        // rethinking the reversed logic throughout - possibly renaming
        // a.sell_amount / a.buy_amount

        _checkPayouts(A);
        takeFundsIntoEscrow(A);

        NewAuction(auction_id, base_id);
    }
}

contract SplittingAuctionManager is AuctionManager, SplittingAuctionFrontend {}
