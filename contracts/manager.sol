import 'erc20/erc20.sol';

import 'auction.sol';
import 'db.sol';
import 'events.sol';
import 'transfer.sol';
import 'types.sol';
import 'util.sol';

contract AuctionController is MathUser
                            , AuctionType
                            , AuctionDatabaseUser
                            , EventfulManager
                            , TransferUser
{
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
    function _makeGenericAuction( address creator
                                , address[] beneficiaries
                                , uint[] payouts
                                , ERC20 selling
                                , ERC20 buying
                                , uint sell_amount
                                , uint start_bid
                                , uint min_increase
                                , uint min_decrease
                                , uint ttl
                                , uint collection_limit
                                , bool reversed
                                )
        internal
        returns (uint auction_id, uint base_id)
    {
        (auction_id, base_id) = newGenericAuction({ creator: msg.sender
                                                  , beneficiaries: beneficiaries
                                                  , payouts: payouts
                                                  , selling: selling
                                                  , buying: buying
                                                  , sell_amount: sell_amount
                                                  , start_bid: start_bid
                                                  , min_increase: min_increase
                                                  , min_decrease: min_decrease
                                                  , ttl: ttl
                                                  , collection_limit: collection_limit
                                                  , reversed: reversed
                                                  });

        var auction = auctions(auction_id);

        assertConsistentPayouts(auction);
        assertSafePercentages(auction);

        takeFundsIntoEscrow(auction);

        LogNewAuction(auction_id, base_id);
    }
    function assertConsistentPayouts(Auction auction)
        internal
    {
        assert(auction.beneficiaries.length == auction.payouts.length);
        if (!auction.reversed) assert(auction.payouts[0] >= auction.start_bid);
        assert(sum(auction.payouts) == auction.collection_limit);
    }
    function assertSafePercentages(Auction auction)
        internal
    {
        // risk of overflow in assertBiddable if these aren't constrained
        assert(auction.min_increase < 100);
        assert(auction.min_decrease < 100);
    }
}

contract AuctionManagerFrontend is AuctionController, MutexUser {
    uint constant INFINITY = uint(-1);
    // Create a new forward auction.
    // Bidding is done through the auctions associated auctionlets,
    // of which there is one initially.
    function newAuction( address beneficiary
                       , address selling
                       , address buying
                       , uint sell_amount
                       , uint start_bid
                       , uint min_increase
                       , uint ttl
                       , uint expiration
                       )
        exclusive
        returns (uint auction_id, uint base_id)
    {
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, INFINITY);

        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: ERC20(selling)
                                                    , buying: ERC20(buying)
                                                    , sell_amount: sell_amount
                                                    , start_bid: start_bid
                                                    , min_increase: min_increase
                                                    , min_decrease: 0
                                                    , ttl: ttl
                                                    , collection_limit: INFINITY
                                                    , reversed: false
                                                    });
        setExpiration(auction_id, expiration);
    }
    function newAuction( address beneficiary
                       , address selling
                       , address buying
                       , uint sell_amount
                       , uint start_bid
                       , uint min_increase
                       , uint ttl
                       )
        exclusive
        returns (uint auction_id, uint base_id)
    {
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, INFINITY);

        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: ERC20(selling)
                                                    , buying: ERC20(buying)
                                                    , sell_amount: sell_amount
                                                    , start_bid: start_bid
                                                    , min_increase: min_increase
                                                    , min_decrease: 0
                                                    , ttl: ttl
                                                    , collection_limit: INFINITY
                                                    , reversed: false
                                                    });
    }
    function newAuction( address[] beneficiaries
                       , uint[] payouts
                       , address selling
                       , address buying
                       , uint sell_amount
                       , uint start_bid
                       , uint min_increase
                       , uint ttl
                       )
        exclusive
        returns (uint auction_id, uint base_id)
    {
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: ERC20(selling)
                                                    , buying: ERC20(buying)
                                                    , sell_amount: sell_amount
                                                    , start_bid: start_bid
                                                    , min_increase: min_increase
                                                    , min_decrease: 0
                                                    , ttl: ttl
                                                    , collection_limit: INFINITY
                                                    , reversed: false
                                                    });
    }
    // Create a new reverse auction
    function newReverseAuction( address beneficiary
                              , address selling
                              , address buying
                              , uint max_sell_amount
                              , uint buy_amount
                              , uint min_decrease
                              , uint ttl
                              )
        exclusive
        returns (uint auction_id, uint base_id)
    {
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, 0);

        // the Reverse Auction is the limit of the two way auction
        // where the maximum collected buying token is zero.
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: ERC20(selling)
                                                    , buying: ERC20(buying)
                                                    , sell_amount: max_sell_amount
                                                    , start_bid: buy_amount
                                                    , min_increase: 0
                                                    , min_decrease: min_decrease
                                                    , ttl: ttl
                                                    , collection_limit: 0
                                                    , reversed: true
                                                    });
    }
    // Create a new reverse auction
    function newReverseAuction( address beneficiary
                              , address refund
                              , address selling
                              , address buying
                              , uint max_sell_amount
                              , uint buy_amount
                              , uint min_decrease
                              , uint ttl
                              )
        exclusive
        returns (uint auction_id, uint base_id)
    {
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, 0);

        // the Reverse Auction is the limit of the two way auction
        // where the maximum collected buying token is zero.
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: ERC20(selling)
                                                    , buying: ERC20(buying)
                                                    , sell_amount: max_sell_amount
                                                    , start_bid: buy_amount
                                                    , min_increase: 0
                                                    , min_decrease: min_decrease
                                                    , ttl: ttl
                                                    , collection_limit: 0
                                                    , reversed: true
                                                    });
        setRefundAddress(auction_id, refund);
    }
    // Create a new two-way auction.
    function newTwoWayAuction( address beneficiary
                             , address selling
                             , address buying
                             , uint sell_amount
                             , uint start_bid
                             , uint min_increase
                             , uint min_decrease
                             , uint ttl
                             , uint collection_limit
                             )
        exclusive
        returns (uint auction_id, uint base_id)
    {
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, collection_limit);
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: ERC20(selling)
                                                    , buying: ERC20(buying)
                                                    , sell_amount: sell_amount
                                                    , start_bid: start_bid
                                                    , min_increase: min_increase
                                                    , min_decrease: min_decrease
                                                    , ttl: ttl
                                                    , collection_limit: collection_limit
                                                    , reversed: false
                                                    });
    }
    function newTwoWayAuction( address beneficiary
                             , address refund
                             , address selling
                             , address buying
                             , uint sell_amount
                             , uint start_bid
                             , uint min_increase
                             , uint min_decrease
                             , uint ttl
                             , uint collection_limit
                             )
        exclusive
        returns (uint auction_id, uint base_id)
    {
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, collection_limit);
        (auction_id, base_id) =  _makeGenericAuction({ creator: msg.sender
                                                     , beneficiaries: beneficiaries
                                                     , payouts: payouts
                                                     , selling: ERC20(selling)
                                                     , buying: ERC20(buying)
                                                     , sell_amount: sell_amount
                                                     , start_bid: start_bid
                                                     , min_increase: min_increase
                                                     , min_decrease: min_decrease
                                                     , ttl: ttl
                                                     , collection_limit: collection_limit
                                                     , reversed: false
                                                     });
        setRefundAddress(auction_id, refund);
    }
    function newTwoWayAuction( address[] beneficiaries
                             , uint[] payouts
                             , address selling
                             , address buying
                             , uint sell_amount
                             , uint start_bid
                             , uint min_increase
                             , uint min_decrease
                             , uint ttl
                             )
        exclusive
        returns (uint auction_id, uint base_id)
    {
        var collection_limit = sum(payouts);
        (auction_id, base_id) =  _makeGenericAuction({ creator: msg.sender
                                                     , beneficiaries: beneficiaries
                                                     , payouts: payouts
                                                     , selling: ERC20(selling)
                                                     , buying: ERC20(buying)
                                                     , sell_amount: sell_amount
                                                     , start_bid: start_bid
                                                     , min_increase: min_increase
                                                     , min_decrease: min_decrease
                                                     , ttl: ttl
                                                     , collection_limit: collection_limit
                                                     , reversed: false
                                                     });
    }
    function newTwoWayAuction( address[] beneficiaries
                             , uint[] payouts
                             , address refund
                             , address selling
                             , address buying
                             , uint sell_amount
                             , uint start_bid
                             , uint min_increase
                             , uint min_decrease
                             , uint ttl
                             )
        exclusive
        returns (uint auction_id, uint base_id)
    {
        var collection_limit = sum(payouts);
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                   , beneficiaries: beneficiaries
                                   , payouts: payouts
                                   , selling: ERC20(selling)
                                   , buying: ERC20(buying)
                                   , sell_amount: sell_amount
                                   , start_bid: start_bid
                                   , min_increase: min_increase
                                   , min_decrease: min_decrease
                                   , ttl: ttl
                                   , collection_limit: collection_limit
                                   , reversed: false
                                   });
        setRefundAddress(auction_id, refund);
    }
}

contract AuctionManager is AuctionManagerFrontend , AuctionFrontend {}
contract SplittingAuctionManager is AuctionManagerFrontend, SplittingAuctionFrontend {}
