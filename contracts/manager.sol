import 'erc20/erc20.sol';

import 'auction.sol';
import 'db.sol';
import 'events.sol';
import 'transfer.sol';
import 'types.sol';
import 'util.sol';

contract AuctionManager is MathUser
                         , AuctionType
                         , AuctionDatabaseUser
                         , EventfulManager
                         , AuctionFrontend
{
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

        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: selling
                                                    , buying: buying
                                                    , sell_amount: sell_amount
                                                    , start_bid: start_bid
                                                    , min_increase: min_increase
                                                    , min_decrease: 0
                                                    , duration: duration
                                                    , collection_limit: INFINITY
                                                    , reversed: false
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
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: selling
                                                    , buying: buying
                                                    , sell_amount: sell_amount
                                                    , start_bid: start_bid
                                                    , min_increase: min_increase
                                                    , min_decrease: 0
                                                    , duration: duration
                                                    , collection_limit: INFINITY
                                                    , reversed: false
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
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: selling
                                                    , buying: buying
                                                    , sell_amount: max_sell_amount
                                                    , start_bid: buy_amount
                                                    , min_increase: 0
                                                    , min_decrease: min_decrease
                                                    , duration: duration
                                                    , collection_limit: 0
                                                    , reversed: true
                                                    });
    }
    // Create a new reverse auction
    function newReverseAuction( address beneficiary
                              , address refund
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
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: selling
                                                    , buying: buying
                                                    , sell_amount: max_sell_amount
                                                    , start_bid: buy_amount
                                                    , min_increase: 0
                                                    , min_decrease: min_decrease
                                                    , duration: duration
                                                    , collection_limit: 0
                                                    , reversed: true
                                                    });
        setRefundAddress(auction_id, refund);
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
        returns (uint auction_id, uint base_id)
    {
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, collection_limit);
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                                    , beneficiaries: beneficiaries
                                                    , payouts: payouts
                                                    , selling: selling
                                                    , buying: buying
                                                    , sell_amount: sell_amount
                                                    , start_bid: start_bid
                                                    , min_increase: min_increase
                                                    , min_decrease: min_decrease
                                                    , duration: duration
                                                    , collection_limit: collection_limit
                                                    , reversed: false
                                                    });
    }
    function newTwoWayAuction( address beneficiary
                             , address refund
                             , ERC20 selling
                             , ERC20 buying
                             , uint sell_amount
                             , uint start_bid
                             , uint min_increase
                             , uint min_decrease
                             , uint duration
                             , uint collection_limit
                             )
        returns (uint auction_id, uint base_id)
    {
        var (beneficiaries, payouts) = _makeSinglePayout(beneficiary, collection_limit);
        (auction_id, base_id) =  _makeGenericAuction({ creator: msg.sender
                                                     , beneficiaries: beneficiaries
                                                     , payouts: payouts
                                                     , selling: selling
                                                     , buying: buying
                                                     , sell_amount: sell_amount
                                                     , start_bid: start_bid
                                                     , min_increase: min_increase
                                                     , min_decrease: min_decrease
                                                     , duration: duration
                                                     , collection_limit: collection_limit
                                                     , reversed: false
                                                     });
        setRefundAddress(auction_id, refund);
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
        returns (uint auction_id, uint base_id)
    {
        var collection_limit = sum(payouts);
        (auction_id, base_id) =  _makeGenericAuction({ creator: msg.sender
                                                     , beneficiaries: beneficiaries
                                                     , payouts: payouts
                                                     , selling: selling
                                                     , buying: buying
                                                     , sell_amount: sell_amount
                                                     , start_bid: start_bid
                                                     , min_increase: min_increase
                                                     , min_decrease: min_decrease
                                                     , duration: duration
                                                     , collection_limit: collection_limit
                                                     , reversed: false
                                                     });
    }
    function newTwoWayAuction( address[] beneficiaries
                             , uint[] payouts
                             , address refund
                             , ERC20 selling
                             , ERC20 buying
                             , uint sell_amount
                             , uint start_bid
                             , uint min_increase
                             , uint min_decrease
                             , uint duration
                             )
        returns (uint auction_id, uint base_id)
    {
        var collection_limit = sum(payouts);
        (auction_id, base_id) = _makeGenericAuction({ creator: msg.sender
                                   , beneficiaries: beneficiaries
                                   , payouts: payouts
                                   , selling: selling
                                   , buying: buying
                                   , sell_amount: sell_amount
                                   , start_bid: start_bid
                                   , min_increase: min_increase
                                   , min_decrease: min_decrease
                                   , duration: duration
                                   , collection_limit: collection_limit
                                   , reversed: false
                                   });
        setRefundAddress(auction_id, refund);
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
    function _makeGenericAuction( address creator
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
        (auction_id, base_id) = newGenericAuction({ creator: msg.sender
                                                  , beneficiaries: beneficiaries
                                                  , payouts: payouts
                                                  , selling: selling
                                                  , buying: buying
                                                  , sell_amount: sell_amount
                                                  , start_bid: start_bid
                                                  , min_increase: min_increase
                                                  , min_decrease: min_decrease
                                                  , duration: duration
                                                  , collection_limit: collection_limit
                                                  , reversed: reversed
                                                  });

        var A = _auctions[auction_id];

        assertConsistentPayouts(A);
        takeFundsIntoEscrow(A);

        NewAuction(auction_id, base_id);
    }
    function assertConsistentPayouts(Auction A) internal {
        assert(A.beneficiaries.length == A.payouts.length);
        if (!A.reversed) assert(A.payouts[0] >= A.start_bid);
        assert(sum(A.payouts) == A.collection_limit);
    }
}

contract SplittingAuctionManager is AuctionManager, SplittingAuctionFrontend {}
