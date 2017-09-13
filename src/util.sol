pragma solidity ^0.4.15;

contract Assertive {
    function assertIncreasing(uint[] array) internal {
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
        if (mutex_lock) throw;
        mutex_lock = true;
        _;
        mutex_lock = false;
    }
}
