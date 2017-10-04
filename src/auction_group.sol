pragma solidity ^0.4.17;

import 'ds-token/base.sol';
import 'ds-math/math.sol';

contract AuctionGroup is DSMath {
    address public creator;
    address[] public members;
    uint[] public milestones;
    uint public paid_out;

    ERC20 private buying;
    ERC20 private selling;

    function AuctionGroup(address selling_, address buying_,
                          address[] members_, uint[] payouts_)
    public
    {
        require(members_.length == payouts_.length);

        creator = msg.sender;
        paid_out = 0;
        members = members_;
        milestones = cumsum(payouts_);
        buying = ERC20(buying_);
        selling = ERC20(selling_);

        // Is this check even relevant anymore?
        // if (!auction.reversed) assert(auction.payouts[0] >= auction.start_bid);
    }

    function payout() public {
        payout(0, milestones.length);
    }

    function payout(uint n, uint m) public {
        require(n < m);

        // Each member has an associated payout, which is the maximum they can
        // receive from the auction. As the auction collects more funds, members
        // may receive their payouts in turn. The per bid settlement could span
        // multiple payouts - the logic below partitions the settlement as
        // needed.

        // collection state prior to this bid
        uint holding = buying.balanceOf(this);
        uint collected = add(holding, paid_out);
        uint limit;
        uint prev_limit;

        for (uint i = n; i < m; i++) {
            prev_limit = (i == 0 ? 0 : milestones[i-1]);
            if (prev_limit >= collected) break; // all available funds distributed?

            limit = milestones[i];
            if (limit <= paid_out) continue; // already paid out?

            // limit is guaranteed to be greater than paid_out.
            // collected = paid_out + holding.
            // limit = pay + paid_out because we would've `continue`d otherwise.
            // Ergo, zeroSub(collected, limit) yields the difference between
            // holding and pay, which yields pay when subtracted from holding.
            var pay = holding
                      - zeroSub(prev_limit, paid_out)
                      - zeroSub(collected, limit);

            require(buying.transfer(members[i], pay));
        }
        paid_out += holding; // Record the payout.
    }

    function claimExcess() public {
        require(msg.sender == creator &&
                paid_out >= milestones[milestones.length-1]);
        require(buying.transfer(creator, buying.balanceOf(this)));
    }

    function zeroSub(uint x, uint y) pure internal returns (uint) {
        if (x > y) return x - y;
        else return 0;
    }

    function cumsum(uint[] array) pure internal returns (uint[]) {
        uint[] memory out = new uint[](array.length);
        out[0] = array[0];
        for (uint i = 1; i < array.length; i++) {
            out[i] = array[i] + out[i - 1];
        }
        return out;
    }
}
