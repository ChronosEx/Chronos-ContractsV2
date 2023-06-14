const { expect } = require("chai");
const chai = require("chai");
const { loadFixture } = require("ethereum-waffle");

const { BN }  = require('bn.js');

const { setupFunctionalTests, setupAccounts } = require("./fixtures.js");
const { mintAndDeposit, mintAndDepositTo, depositAll, mint, increase, split, merge, withdraw, withdrawAll, calculateNewEntry, multiplier, increaseTime, MATURITY_PRECISION } = require("./helpers.js");
const { testError } = require("./test_helpers.js");
const { BigNumber } = require("ethers");

chai.use(require('chai-bn')(BN));

// shared state, used to calculate expected weight
let depositAmounts = [];
let entries = [];

describe("MaGaugeV2Upgradeable: Maturity-related basic functional tests", function () {

    it("New contract was deployed", async function() {
        const { _token, maNFT } = await loadFixture(setupFunctionalTests);
        expect(await maNFT.totalSupply()).to.equal(0);
    });

    it("Deposit", async function() {
        const { _token, maNFT } = await loadFixture(setupFunctionalTests);
        const { acc1, acc2, acc3 } = await loadFixture(setupAccounts);

        // making a deposit by one of the accounts
        let amount = BigNumber.from("1000000000000000000");

        let lpSupply = await maNFT.lpTotalSupply();
        let totalSupply = await maNFT.totalSupply();

        let id = await mintAndDeposit(acc1, amount.toString(), _token, maNFT);

        // checking NFT balance is as expected
        let nftBalance = await maNFT.lpBalanceOfmaNFT(id);
        let expectedBalance = BigNumber.from(lpSupply).add(amount);

        expect(BigNumber.from(nftBalance)).to.equal(BigNumber.from(amount));
        
        depositAmounts[id] = amount;

        // storing the deposited entry for future tests and for expected weight calculation
        let lastUpdateTimePostDeposit = await maNFT._lastTotalWeightUpdateTime();

        entries[id] = lastUpdateTimePostDeposit;

        // checking LP supply is increased as expected
        let lpSupplyPostDeposit = await maNFT.lpTotalSupply();
        
        expect(BigNumber.from(lpSupplyPostDeposit)).to.equal(expectedBalance);

        // checking NFT supply is increased as expected
        let totalSupplyPostDeposit = await maNFT.totalSupply();

        expect(totalSupplyPostDeposit).to.equal(BigNumber.from(totalSupply).add(1));

        // checking the NFT weight is as expected
        let nftWeight = await maNFT.maNFTWeight(id);

        let expectedWeight = BigNumber.from(amount).mul(BigNumber.from(MATURITY_PRECISION));

        expect(BigNumber.from(nftWeight)).to.equal(expectedWeight);

        // checking NFT ownership is as expected
        let nftOwner = await maNFT.ownerOf(id);

        expect(nftOwner.toString()).to.be.equal(acc1.address);

        // checking total weight is as expected
        let totalWeightPostDeposit = await maNFT.totalWeight();

        var expectedTotalWeight = BigNumber.from(0);

        for (var i in entries) {
            expectedTotalWeight = expectedTotalWeight.add(
                BigNumber.from(depositAmounts[i]).mul(BigNumber.from(multiplier(entries[i], lastUpdateTimePostDeposit)))
            );
        }

        // it is expected to have an error in weight increment due to the maturity precision
        testError(expectedTotalWeight, totalWeightPostDeposit);

        await increaseTime(3600);
    });

    it("Deposit All", async function() {
        const { _token, maNFT } = await loadFixture(setupFunctionalTests);
        const { acc1, acc2, acc3 } = await loadFixture(setupAccounts);

        let amount = BigNumber.from("5000000000000000000");

        let lpSupply = await maNFT.lpTotalSupply();
        let totalSupply = await maNFT.totalSupply();
        
        // minting new tokens to account
        await mint(acc2, amount.toString(), _token);

        let accountBalance = await _token.balanceOf(acc2.address);

        let id = await depositAll(acc2, _token, maNFT);

        // checking NFT balance is as expected
        let nftBalance = await maNFT.lpBalanceOfmaNFT(id);

        expect(BigNumber.from(nftBalance)).to.equal(BigNumber.from(accountBalance));

        depositAmounts[id] = accountBalance;

        // storing the deposited entry for future tests and for expected weight calculation
        let lastUpdateTimePostDeposit = await maNFT._lastTotalWeightUpdateTime();

        entries[id] = lastUpdateTimePostDeposit;

        // checking LP supply is increased as expected
        let lpSupplyPostDeposit = await maNFT.lpTotalSupply();
        let expectedBalance = BigNumber.from(lpSupply).add(accountBalance);

        expect(BigNumber.from(lpSupplyPostDeposit)).to.equal(expectedBalance);

        // checking NFT supply is increased as expected
        let totalSupplyPostDeposit = await maNFT.totalSupply();

        expect(totalSupplyPostDeposit).to.equal(BigNumber.from(totalSupply).add(1));

        // checking the NFT weight is as expected
        let nftWeight = await maNFT.maNFTWeight(id);

        let expectedWeight = BigNumber.from(accountBalance).mul(BigNumber.from(MATURITY_PRECISION));
        expect(BigNumber.from(nftWeight)).to.equal(expectedWeight);

        // checking NFT ownership is as expected
        let nftOwner = await maNFT.ownerOf(id);

        expect(nftOwner.toString()).to.be.equal(acc2.address);

        // checking total weight is as expected
        let totalWeightPostDeposit = await maNFT.totalWeight();

        var expectedTotalWeight = BigNumber.from(0);
        for (var i in entries) {
            expectedTotalWeight = expectedTotalWeight.add(
                BigNumber.from(depositAmounts[i]).mul(BigNumber.from(multiplier(entries[i], lastUpdateTimePostDeposit)))
            );
        }

        // it is expected to have an error in weight increment due to the maturity precision
        testError(expectedTotalWeight, totalWeightPostDeposit);

        await increaseTime(86400);
    });

    it("Deposit to", async function() {
        const { _token, maNFT } = await loadFixture(setupFunctionalTests);
        const { acc1, acc2, acc3 } = await loadFixture(setupAccounts);

        let amount = BigNumber.from("8000000000000000000");

        let lpSupply = await maNFT.lpTotalSupply();
        let totalSupply = await maNFT.totalSupply();

        let id = await mintAndDepositTo(acc2, acc1, amount.toString(), _token, maNFT);

        // checking NFT balance is as expected
        let nftBalance = await maNFT.lpBalanceOfmaNFT(id);

        expect(BigNumber.from(nftBalance)).to.equal(BigNumber.from(amount));

        depositAmounts[id] = amount;

        // storing the deposited entry for future tests and for expected weight calculation
        let lastUpdateTimePostDeposit = await maNFT._lastTotalWeightUpdateTime();

        entries[id] = lastUpdateTimePostDeposit;

        // checking LP supply is increased as expected
        let lpSupplyPostDeposit = await maNFT.lpTotalSupply();
        let expectedBalance = BigNumber.from(lpSupply).add(amount);

        expect(BigNumber.from(lpSupplyPostDeposit)).to.equal(expectedBalance);

        // checking NFT supply is increased as expected
        let totalSupplyPostDeposit = await maNFT.totalSupply();

        expect(totalSupplyPostDeposit).to.equal(BigNumber.from(totalSupply).add(1));

        // checking the NFT weight is as expected
        let nftWeight = await maNFT.maNFTWeight(id);
        let expectedWeight = BigNumber.from(amount).mul(BigNumber.from(MATURITY_PRECISION));

        expect(BigNumber.from(nftWeight)).to.equal(expectedWeight);

        // checking NFT ownership is as expected
        let nftOwner = await maNFT.ownerOf(id);

        expect(nftOwner.toString()).to.be.equal(acc1.address);

        // checking total weight is as expected
        let totalWeightPostDeposit = await maNFT.totalWeight();

        var expectedTotalWeight = BigNumber.from(0);

        for (var i in entries) {
            expectedTotalWeight = expectedTotalWeight.add(
                BigNumber.from(depositAmounts[i]).mul(BigNumber.from(multiplier(entries[i], lastUpdateTimePostDeposit)))
            );
        }

        // it is expected to have an error in weight increment due to the maturity precision
        testError(expectedTotalWeight, totalWeightPostDeposit);

        await increaseTime(86400 * 3);
    });

    it("Increase", async function() {
        const { _token, maNFT } = await loadFixture(setupFunctionalTests);
        const { acc1, acc2, acc3 } = await loadFixture(setupAccounts);

        let newAmount = BigNumber.from("4000000000000000000");
        let id = 1;

        let lpPreIncrease = await maNFT.lpBalanceOfmaNFT(id);
        let entryPreIncrease = await maNFT._positionEntries(id);
        let lpSupplyPreIncrease = await maNFT.lpTotalSupply();

        let nftSupplyPreIncrease = await maNFT.totalSupply();

        await increase(acc1, id, newAmount.toString(), _token, maNFT);

        // checking NFT LP is as expected
        let lpPostIncrease = await maNFT.lpBalanceOfmaNFT(id);

        expect(BigNumber.from(lpPostIncrease)).to.be.equal(BigNumber.from(lpPreIncrease).add(newAmount));

        depositAmounts[id] = depositAmounts[id].add(newAmount);

        // checking total LP supply is as expected
        let lpSupplyPostIncrease = await maNFT.lpTotalSupply();

        expect(BigNumber.from(lpSupplyPostIncrease)).to.be.equal(BigNumber.from(lpSupplyPreIncrease).add(newAmount));

        // checking the entry after increase is updated as expected
        let lastUpdateTime = await maNFT._lastTotalWeightUpdateTime();
        let expectedEntry = calculateNewEntry(lpPreIncrease, newAmount, entryPreIncrease, lastUpdateTime);
        let actualEntry = await maNFT._positionEntries(id);

        expect(BigNumber.from(actualEntry)).to.be.equal(expectedEntry);

        entries[id] = expectedEntry;

        // checking NFT weight is updated as expected
        let expectedWeight = BigNumber.from(depositAmounts[id]).mul(multiplier(expectedEntry, lastUpdateTime));
        let actualWeight = await maNFT.maNFTWeight(id);

        expect(BigNumber.from(actualWeight)).to.be.equal(expectedWeight);

        // checking NFTs supply hasn't changed
        let nftSupplyPostIncrease = await maNFT.totalSupply();

        expect(BigNumber.from(nftSupplyPostIncrease)).to.be.equal(BigNumber.from(nftSupplyPreIncrease));

        // checking total weight is updated as expected
        var expectedTotalWeight = BigNumber.from(0);

        for (var i in entries) {
            expectedTotalWeight = expectedTotalWeight.add(
                BigNumber.from(depositAmounts[i]).mul(BigNumber.from(multiplier(entries[i], lastUpdateTime)))
            );
        }

        let actualTotalWeight = await maNFT.totalWeight();
        testError(expectedTotalWeight, actualTotalWeight);

        await increaseTime(86400 * 9);
    });

    it("Split", async function() {
        const { _token, maNFT } = await loadFixture(setupFunctionalTests);
        const { acc1, acc2, acc3 } = await loadFixture(setupAccounts);

        let weights = [1000, 2000, 500, 1, 39, 460, 2000, 1000, 1000, 1995, 5];
        let id = 1;

        let entryPreSplit = await maNFT._positionEntries(id);
        let tokenId = await maNFT.tokenId();
        let preSplitLP = await maNFT.lpBalanceOfmaNFT(id);

        let nftSupplyPreSplit = await maNFT.totalSupply();

        await split(acc1, id, weights, maNFT);

        // calculating the expected weight = weight of old splitted position
        let lastUpdateTime = await maNFT._lastTotalWeightUpdateTime();
        let expectedWeight = BigNumber.from(preSplitLP).mul(multiplier(entryPreSplit, lastUpdateTime));

        let expectedSplitBalances = weights.map((value) => BigNumber.from(value).mul(BigNumber.from(preSplitLP)).div(10000));

        // checking old entry was deleted
        let oldNFTLP = await maNFT.lpBalanceOfmaNFT(id);
        let oldNFTEntry = await maNFT._positionEntries(id);
        let oldNFTWeight = await maNFT.maNFTWeight(id);

        expect(BigNumber.from(oldNFTWeight)).to.be.equal(0);
        expect(BigNumber.from(oldNFTLP)).to.be.equal(0);
        expect(oldNFTEntry).to.be.equal(0);

        // removing position from state 
        depositAmounts[id] = 0;
        entries[id] = 0;

        // checking balances, weights and entries of new positions
        var currentTokenId = tokenId;
        var totalSplitWeight = BigNumber.from(0);
        for (var i = 0; i < weights.length; i++) {
            let actualLP = await maNFT.lpBalanceOfmaNFT(currentTokenId);
            expect(BigNumber.from(actualLP)).to.be.equal(BigNumber.from(expectedSplitBalances[i]));

            let actualWeight = await maNFT.maNFTWeight(currentTokenId);
            let expectedWeight =  BigNumber.from(actualLP).mul(multiplier(entryPreSplit, lastUpdateTime));

            let actualPositionEntry = await maNFT._positionEntries(currentTokenId);
            expect(BigNumber.from(actualPositionEntry)).to.be.equal(entryPreSplit);
            expect(BigNumber.from(actualWeight)).to.be.equal(expectedWeight);

            totalSplitWeight = totalSplitWeight.add(BigNumber.from(actualWeight));

            depositAmounts[currentTokenId] = actualLP;
            entries[currentTokenId] = actualPositionEntry;
            currentTokenId++;
        }

        // checking the sum of new positions weights is equal to the expected weight
        expect(totalSplitWeight).to.be.equal(expectedWeight);

        // checking the total weight of the pool is as expected
        var expectedTotalWeight = BigNumber.from(0);

        for (var i in entries) {
            expectedTotalWeight = expectedTotalWeight.add(
                BigNumber.from(depositAmounts[i]).mul(BigNumber.from(multiplier(entries[i], lastUpdateTime)))
            );
        }

        let actualTotalWeight = await maNFT.totalWeight();
        testError(expectedTotalWeight, actualTotalWeight);

        // checking NFTs supply
        let nftSupplyPostSplit = await maNFT.totalSupply();

        expect(BigNumber.from(nftSupplyPostSplit)).to.be.equal(BigNumber.from(nftSupplyPreSplit).add(weights.length - 1));

        await increaseTime(86400 * 6);
    });

    it("Merge", async function() {
        const { _token, maNFT } = await loadFixture(setupFunctionalTests);
        const { acc1, acc2, acc3 } = await loadFixture(setupAccounts);

        let tokensOfOwner = await maNFT.tokensOfOwner(acc1.address);
        let sortedTokens = [ ...tokensOfOwner].sort((a,b) => { return a.sub(b) });

        let idFrom = sortedTokens[0]; // supposedly id 3 
        let idTo = sortedTokens[tokensOfOwner.length - 1]; // supposedly last splitted id

        let lpFromPreMerge = await maNFT.lpBalanceOfmaNFT(idFrom);
        let lpToPreMerge = await maNFT.lpBalanceOfmaNFT(idTo);

        let lpSupplyPreMerge = await maNFT.lpTotalSupply();

        let oldEntryFrom = await maNFT._positionEntries(idFrom);
        let oldEntryTo = await maNFT._positionEntries(idTo);

        let nftSupplyPreMerge= await maNFT.totalSupply();

        await merge(acc1, idFrom, idTo, maNFT);

        // checking LP supply of pool didn't change
        let lpSupplyPostMerge = await maNFT.lpTotalSupply();

        expect(BigNumber.from(lpSupplyPostMerge)).to.be.equal(BigNumber.from(lpSupplyPreMerge));

        // checking old NFT balances were deleted
        let lpFromPostMerge = await maNFT.lpBalanceOfmaNFT(idFrom);
        let weightFromPostMerge = await maNFT.maNFTWeight(idFrom);
        let positionFromPostMerge = await maNFT._positionEntries(idFrom);

        expect(BigNumber.from(lpFromPostMerge)).to.be.equal(0);
        expect(BigNumber.from(weightFromPostMerge)).to.be.equal(0);
        expect(BigNumber.from(positionFromPostMerge)).to.be.equal(0);

        depositAmounts[idFrom] = 0;
        entries[idFrom] = 0;

        // checking new NFT balance is correct
        let lpToPostMerge = await maNFT.lpBalanceOfmaNFT(idTo);

        let lastUpdateTime = await maNFT._lastTotalWeightUpdateTime();

        expect(BigNumber.from(lpToPostMerge)).to.be.equal(BigNumber.from(lpToPreMerge).add(BigNumber.from(lpFromPreMerge)));

        depositAmounts[idTo] = lpToPostMerge;

        // checking entry is correct
        let expectedEntry = calculateNewEntry(lpToPreMerge, lpFromPreMerge, oldEntryFrom, oldEntryTo);
        let actualEntry = await maNFT._positionEntries(idTo);

        expect(BigNumber.from(actualEntry)).to.be.equal(expectedEntry);

        entries[idTo] = expectedEntry;

        // checking weight of new position
        let expectedWeight = BigNumber.from(lpToPostMerge).mul(multiplier(expectedEntry, lastUpdateTime));
        let actualWeight = await maNFT.maNFTWeight(idTo);

        expect(BigNumber.from(actualWeight)).to.be.equal(expectedWeight);

        // checking total weight
        var expectedTotalWeight = BigNumber.from(0);

        for (var i in entries) {
            expectedTotalWeight = expectedTotalWeight.add(
                BigNumber.from(depositAmounts[i]).mul(BigNumber.from(multiplier(entries[i], lastUpdateTime)))
            );
        }

        let actualTotalWeight = await maNFT.totalWeight();
        testError(expectedTotalWeight, actualTotalWeight);

        // checking NFTs supply
        let nftSupplyPostMerge = await maNFT.totalSupply();

        expect(BigNumber.from(nftSupplyPostMerge)).to.be.equal(BigNumber.from(nftSupplyPreMerge).sub(1));

        await increaseTime(86400 * 3);
    });

    it("Withdraw", async function() {
        const { _token, maNFT } = await loadFixture(setupFunctionalTests);
        const { acc1, acc2, acc3 } = await loadFixture(setupAccounts);

        let tokensOfOwner = await maNFT.tokensOfOwner(acc1.address);
        let sortedTokens = [ ...tokensOfOwner].sort((a,b) => { return a.sub(b) });

        let id = sortedTokens[0];

        let amountToWithdraw = await maNFT.lpBalanceOfmaNFT(id);
        let lpPreWithdraw = await maNFT.lpTotalSupply();

        let balancePreWithdraw = BigNumber.from(await _token.balanceOf(acc1.address));

        let nftSupplyPreWithdraw = await maNFT.totalSupply();

        await withdraw(acc1, id, maNFT);

        let lastUpdateTime = await maNFT._lastTotalWeightUpdateTime();

        let positionLPPostWithdraw = await maNFT.lpBalanceOfmaNFT(id);
        let lpPostWithdraw = await maNFT.lpTotalSupply();

        // checking balance of LP and user balance has changed correctly
        let balancePostWithdraw = await _token.balanceOf(acc1.address);
        expect(BigNumber.from(balancePostWithdraw)).to.be.equal(BigNumber.from(balancePreWithdraw).add(amountToWithdraw));
        expect(BigNumber.from(lpPostWithdraw)).to.be.equal(BigNumber.from(lpPreWithdraw).sub(amountToWithdraw));
        expect(BigNumber.from(positionLPPostWithdraw)).to.be.equal(0);

        depositAmounts[id] = 0;
        entries[id] = 0;

        // checking entry is 0
        let positionEntry = await maNFT._positionEntries(id);

        expect(BigNumber.from(positionEntry)).to.be.equal(0);

        // checking position weight is 0
        let positionWeightPostWithdraw = await maNFT.maNFTWeight(id);

        expect(BigNumber.from(positionWeightPostWithdraw)).to.be.equal(0);

        // checking total weight
        var expectedTotalWeight = BigNumber.from(0);

        for (var i in entries) {
            expectedTotalWeight = expectedTotalWeight.add(
                BigNumber.from(depositAmounts[i]).mul(BigNumber.from(multiplier(entries[i], lastUpdateTime)))
            );
        }

        let actualTotalWeight = await maNFT.totalWeight();
        testError(expectedTotalWeight, actualTotalWeight);

        // checking NFTs supply
        let nftSupplyPostWithdraw = await maNFT.totalSupply();

        expect(BigNumber.from(nftSupplyPostWithdraw)).to.be.equal(BigNumber.from(nftSupplyPreWithdraw).sub(1));

        await increaseTime(86400 * 4);
    });

    it("Withdraw All", async function() {
        const { _token, maNFT } = await loadFixture(setupFunctionalTests);
        const { acc1, acc2, acc3 } = await loadFixture(setupAccounts);

        let tokensOfOwner = await maNFT.tokensOfOwner(acc1.address);

        var expectedWithdrawnAmount = BigNumber.from(0);

        for (var i in tokensOfOwner) {
            let lp = await maNFT.lpBalanceOfmaNFT(tokensOfOwner[i]);
            expectedWithdrawnAmount = expectedWithdrawnAmount.add(BigNumber.from(lp));
        }

        let lpPreWithdraw = await maNFT.lpTotalSupply();
        let balancePreWithdraw = BigNumber.from(await _token.balanceOf(acc1.address));

        let nftSupplyPreWithdraw = await maNFT.totalSupply();

        await withdrawAll(acc1, maNFT);

        let lastUpdateTime = await maNFT._lastTotalWeightUpdateTime();
        let lpPostWithdraw = await maNFT.lpTotalSupply();

        // checking balance of LP and user balance has changed correctly
        let balancePostWithdraw = await _token.balanceOf(acc1.address);
        expect(BigNumber.from(balancePostWithdraw)).to.be.equal(BigNumber.from(balancePreWithdraw).add(expectedWithdrawnAmount));
        expect(BigNumber.from(lpPostWithdraw)).to.be.equal(BigNumber.from(lpPreWithdraw).sub(expectedWithdrawnAmount));

        // checking individual tokens state
        for (var i in tokensOfOwner) {
            let weight = await maNFT.maNFTWeight(tokensOfOwner[i]);
            let lp = await maNFT.lpBalanceOfmaNFT(tokensOfOwner[i]);
            let entry = await maNFT._positionEntries(tokensOfOwner[i]);
            
            expect(BigNumber.from(weight)).to.be.equal(0);
            expect(BigNumber.from(lp)).to.be.equal(0);
            expect(BigNumber.from(entry)).to.be.equal(0);

            depositAmounts[tokensOfOwner[i]] = 0;
            entries[tokensOfOwner[i]] = 0;
        }
        // checking total weight
        var expectedTotalWeight = BigNumber.from(0);

        for (var i in entries) {
            expectedTotalWeight = expectedTotalWeight.add(
                BigNumber.from(depositAmounts[i]).mul(BigNumber.from(multiplier(entries[i], lastUpdateTime)))
            );
        }

        let actualTotalWeight = await maNFT.totalWeight();
        let error = testError(expectedTotalWeight, actualTotalWeight);

        // checking NFTs supply
        let nftSupplyPostWithdraw = await maNFT.totalSupply();

        expect(BigNumber.from(nftSupplyPostWithdraw)).to.be.equal(BigNumber.from(nftSupplyPreWithdraw).sub(tokensOfOwner.length));

        await increaseTime(86400 * 4);
    });

});