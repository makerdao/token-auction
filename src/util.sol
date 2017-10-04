pragma solidity ^0.4.17;

contract Assertive {
    function assertIncreasing(uint[] array) internal pure {
        if (array.length < 2) return;

        for (uint i = 1; i < array.length; i ++) {
            assert(array[i] > array[i - 1]);
        }
    }
}

contract TimeUser {
    // Using this allows override of the block timestamp in tests
    function getTime() public constant returns (uint64) {
        return uint64(block.timestamp);
    }
}

contract MutexUser {
    bool private mutex_lock;
    modifier exclusive {
        assert(!mutex_lock);
        mutex_lock = true;
        _;
        mutex_lock = false;
    }
}
