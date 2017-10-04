pragma solidity ^0.4.17;

import 'ds-token/base.sol';

import './auction.sol';
import './db.sol';
import './events.sol';
import './types.sol';
import './util.sol';

contract AuctionController is AuctionType
                            , AuctionDatabaseUser
                            , EventfulManager
{
    function _makeGenericAuction( address creator
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
        (auction_id, base_id) = newGenericAuction({ creator: msg.sender
                                                  , beneficiary: beneficiary
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

        assertSafePercentages(auction);

        // Escrow funds.
        assert(selling.transferFrom(creator, this, sell_amount));

        LogNewAuction(auction_id, base_id);
    }
    function assertSafePercentages(Auction auction)
        pure
        internal
    {
        // risk of overflow in assertBiddable if these aren't constrained
        assert(auction.min_increase < 100);
        assert(auction.min_decrease < 100);
    }
}

contract AuctionManagerFrontend is AuctionController, MutexUser {
    uint constant INFINITY = uint(uint128(-1));
    uint64 constant INFINITY_64 = uint64(-1);

    // Create a new forward auction.
    // Bidding is done through the auctions associated auctionlets,
    // of which there is one initially.
    function newAuction( address beneficiary
                       , address selling
                       , address buying
                       , uint sell_amount
                       , uint start_bid
                       , uint min_increase
                       , uint64 ttl
                       , uint64 expiration
                       )
        public
        exclusive
        returns (uint auction_id, uint base_id)
    {
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiary: beneficiary
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
                       , uint64 ttl
                       )
        public
        exclusive
        returns (uint auction_id, uint base_id)
    {
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiary: beneficiary
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
                              , uint64 ttl
                              )
        public
        exclusive
        returns (uint auction_id, uint base_id)
    {
        // the Reverse Auction is the limit of the two way auction
        // where the maximum collected buying token is zero.
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiary: beneficiary
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
                              , uint64 ttl
                              )
        public
        exclusive
        returns (uint auction_id, uint base_id)
    {
        // the Reverse Auction is the limit of the two way auction
        // where the maximum collected buying token is zero.
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiary: beneficiary
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
                             , uint64 ttl
                             , uint collection_limit
                             )
        public
        exclusive
        returns (uint auction_id, uint base_id)
    {
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiary: beneficiary
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
                             , uint64 ttl
                             , uint collection_limit
                             )
        public
        exclusive
        returns (uint auction_id, uint base_id)
    {
        (auction_id, base_id) =  _makeGenericAuction({ creator: msg.sender
                                                     , beneficiary: beneficiary
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
