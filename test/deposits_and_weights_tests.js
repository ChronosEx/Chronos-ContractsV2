const { ethers } = require("hardhat")
const { expect } = require("chai");
const chai = require("chai");
const { loadFixture } = require("ethereum-waffle");
const { BigNumber } = require("ethers");

const { BN }  = require('bn.js');
chai.use(require('chai-bn')(BN));

const { setupDepositsWeightsTests, setupAccounts } = require("./fixtures.js");
const { mintAndDeposit, withdrawAll, multiplier, sync, increaseTime } = require("./helpers.js");
const { testError } = require("./test_helpers.js");

describe("MaGaugeV2Upgradeable: Deposits and weights tests", function () {

    it("New contract was deployed", async function() {
        const { _token, maNFT } = await loadFixture(setupDepositsWeightsTests);
        expect(await maNFT.totalSupply()).to.equal(0);
    });

    it("Weights are correct in between deposits and after sync", async function() {
        const { _token, maNFT } = await loadFixture(setupDepositsWeightsTests);
        const { acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10 } = await loadFixture(setupAccounts);

        let accounts = [acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10];

        let expectedLPSupply = BigNumber.from(0);

        let count = 400;
        let maxDelta = 3628800;

        let depositAmounts = [];
        let deltas = [];

        let positions = [];
        let entries = [];

        // prepare test data for executing deposits
        for (var i = 0; i < count; i++) {
            depositAmounts[i] = BigNumber.from("1000000000000000000").mul(Math.floor(Math.random() * 1000) + 1);
            deltas[i] = Math.floor(Math.random() * maxDelta);
        }

        let lastUpdateTime = 0;

        for (var i in depositAmounts) {
            // making a deposit
            var amount = BigNumber.from(depositAmounts[i]);
            let account = accounts[Math.floor(Math.random() * (accounts.length - 1))];
            console.log("Making a deposit of " + amount + " from " + account.address);
            let id = await mintAndDeposit(account, amount, _token, maNFT);

            console.log("Deposited " + amount + " to NFT id " + id);

            expectedLPSupply = expectedLPSupply.add(amount);

            // checking LP balance validity
            expect(await maNFT.lpTotalSupply()).to.equal(expectedLPSupply);
            expect(await maNFT.lpBalanceOfmaNFT(id)).to.equal(amount);

            // checking individual weights validity
            let updateTime = await maNFT._positionEntries(id);
            entries[i] = updateTime;
            positions[i] = id;

            lastUpdateTime = updateTime;

            var expectedTotal = BigNumber.from("0");
            for (var j = 0; j < positions.length; j++) {
                let expectedWeight = BigNumber.from(depositAmounts[j]).mul(multiplier(entries[j], lastUpdateTime));
                expectedTotal = expectedTotal.add(expectedWeight);
                let actualWeight = await maNFT.maNFTWeight(positions[j]);

                expect(actualWeight).to.equal(expectedWeight);
            }

            // checking total weight validity
            let actualTotalWeight = await maNFT.totalWeight();

            // it is expected to have an error in weight increment due to the maturity precision
            let error = testError(expectedTotal, actualTotalWeight);
            console.log("Exp weight = " + expectedTotal);
            console.log("Act weight = " + actualTotalWeight);
            console.log("Error = " + error);

            console.log("----")

            console.log("Increasing time by " + deltas[i]);

            await increaseTime(deltas[i]);

            console.log("----")
        };

        console.log("Post-deposits check");
        await sync(acc1, maNFT);

        let updateTime = await maNFT._lastTotalWeightUpdateTime();

        // check individual positions weights
        var expectedTotal = BigNumber.from("0");
        for (var j = 0; j < positions.length; j++) {
            let expectedWeight = BigNumber.from(depositAmounts[j]).mul(multiplier(entries[j], updateTime));
            expectedTotal = expectedTotal.add(expectedWeight);

            let actualWeight = await maNFT.maNFTWeight(positions[j]);

            expect(actualWeight).to.equal(expectedWeight);
        }

        // check total weight
        let actualTotalWeight = await maNFT.totalWeight();

        // it is expected to have an error in total weight due to the maturity precision
        // and the lack of calculation precision when calculating multiplier
        let error = testError(expectedTotal, actualTotalWeight);
        console.log("Exp weight = " + expectedTotal);
        console.log("Act weight = " + actualTotalWeight);
        console.log("Error = " + error);

    });

    it("Withdraw all", async function() {
        const { _token, maNFT } = await loadFixture(setupDepositsWeightsTests);
        const { acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10 } = await loadFixture(setupAccounts);

        let accounts = [acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10];

        for (var i in accounts) {
            console.log("Withdrawing all for " + accounts[i].address);
            let balance = BigNumber.from(await _token.balanceOf(accounts[i].address));
            let lp = await maNFT.lpTotalSupply();

            let tokensOfOwner = await maNFT.tokensOfOwner(accounts[i].address);

            var expectedWithdrawnAmount = BigNumber.from(0);

            for (var j in tokensOfOwner) {
                let lpCurrent = await maNFT.lpBalanceOfmaNFT(tokensOfOwner[j]);
                expectedWithdrawnAmount = expectedWithdrawnAmount.add(BigNumber.from(lpCurrent));
            }

            await withdrawAll(accounts[i], maNFT);

            let balancePostWithdraw = BigNumber.from(await _token.balanceOf(accounts[i].address));
            let lpPostWithdraw = await maNFT.lpTotalSupply();

            expect(balancePostWithdraw).to.be.equal(BigNumber.from(balance).add(expectedWithdrawnAmount));
            expect(BigNumber.from(lpPostWithdraw)).to.be.equal(BigNumber.from(lp).sub(expectedWithdrawnAmount));
        }

        let weightPostWithdraw = await maNFT.totalWeight();

        expect(weightPostWithdraw).to.be.equal(0);
        expect(await maNFT._weightIncrement()).to.be.equal(0);        
    });
});