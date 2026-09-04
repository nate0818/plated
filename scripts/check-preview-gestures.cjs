// Run against the sample design preview with Playwright and Chrome installed.
// The test uses a fresh temporary browser profile; it never opens the user profile.
const assert=require('node:assert/strict');
const { chromium } = require('playwright');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try {
 const page=await browser.newPage({viewport:{width:413,height:959},hasTouch:true});
 
 page.setDefaultTimeout(7000);const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(process.env.PLATED_PREVIEW_URL||'http://127.0.0.1:8769/');
 const f=page.frameLocator('iframe'), row=f.locator('.p-swipe').first();
 await row.waitFor();const b=await row.boundingBox(),y=b.y+b.height/2;
 async function opened(expected){await page.waitForTimeout(350);assert.equal(await row.getAttribute('data-open'),String(expected))}
 async function drag(x1,y1,x2,y2){await page.mouse.move(x1,y1);await page.mouse.down();await page.mouse.move(x2,y2,{steps:15});await page.mouse.up()}
 await drag(b.x+b.width-70,y,b.x+35,y);await opened(true);console.log('PASS pointer swipe reveals actions');
 assert.deepEqual((await row.locator('.p-swipe-under').innerText()).split('\n'),['Edit','Move','Remove']);
 await row.locator('[data-reveal-swipe]').click();await opened(false);
 await drag(b.x+230,y,b.x+232,y-50);await opened(false);console.log('PASS vertical drag does not reveal actions');
 await row.locator('[data-reveal-swipe]').focus();await page.keyboard.press('ArrowLeft');await opened(true);await page.keyboard.press('Escape');await opened(false);console.log('PASS keyboard reveal and dismissal');
 await page.mouse.move(b.x+200,y);await page.mouse.wheel(230,0);await opened(true);await page.mouse.wheel(-230,0);await opened(false);console.log('PASS trackpad opens and closes');
 const session=await page.context().newCDPSession(page);
 async function touch(type,x,y){await session.send('Input.dispatchTouchEvent',{type,touchPoints:['touchEnd','touchCancel'].includes(type)?[]:[{x,y,id:1,radiusX:3,radiusY:3}]})}
 await touch('touchStart',b.x+260,y);for(let n=1;n<=14;n++){await touch('touchMove',b.x+260-n*15,y);await page.waitForTimeout(12)}await touch('touchEnd');await opened(true);console.log('PASS touch swipe reveals actions');
 await touch('touchStart',b.x+65,y);await touch('touchMove',b.x+110,y);await touch('touchCancel');await opened(true);console.log('PASS cancelled touch preserves open state');
 await f.getByRole('heading',{name:'Your week',exact:true}).click();await opened(false);console.log('PASS outside tap closes tray');
 await row.locator('[data-reveal-swipe]').click();await row.getByRole('button',{name:'Move',exact:true}).click();
 assert.equal(await f.getByRole('button',{name:'Move dinner',exact:true}).isDisabled(),true);
 await f.locator('[data-move-day="2026-09-05"]').click();assert.match(await f.locator('.p-sheet').innerText(),/two dinners will swap/);
 await f.getByRole('button',{name:'Swap dinners',exact:true}).click();
 assert.match(await row.innerText(),/Tomato/);
 assert.match(await row.innerText(),/Sam cooks · 4 servings/);
 await f.getByRole('button',{name:'Undo',exact:true}).click();assert.match(await row.innerText(),/Salmon/);console.log('PASS occupied-date swap preserves details and Undo restores dates');
 await row.locator('[data-reveal-swipe]').click();await row.getByRole('button',{name:'Remove',exact:true}).click();assert.equal(await f.getByRole('button',{name:'Actions for Salmon with lemon butter, Tonight',exact:true}).count(),0);
 await f.getByRole('button',{name:'Undo',exact:true}).click();assert.match(await row.innerText(),/Salmon/);console.log('PASS Remove and Undo');
 await row.locator('[data-reveal-swipe]').click();await row.getByRole('button',{name:'Edit',exact:true}).click();
 await f.getByRole('spinbutton',{name:'Servings',exact:true}).fill('6');await f.getByLabel('Cook',{exact:true}).selectOption('Sam');
 await f.getByRole('button',{name:'Update dinner and groceries',exact:true}).click();assert.match(await row.innerText(),/Sam cooks · 6 servings/);
 await f.getByRole('button',{name:'Undo',exact:true}).click();console.log('PASS Edit updates servings and cook');
 await f.locator('[data-action="calendar-mode:month"]').click();const monthRow=f.locator('.p-swipe').first();await monthRow.locator('[data-reveal-swipe]').click();
 assert.deepEqual((await monthRow.locator('.p-swipe-under').innerText()).split('\n'),['Edit','Move','Remove']);console.log('PASS Month agenda has matching dinner actions');
 await f.locator('[data-action="calendar-mode:week"]').click();
 await f.getByRole('button',{name:'Next week',exact:true}).click();
 const empty=f.locator('.p-swipe').first();await empty.locator('[data-reveal-swipe]').click();await empty.getByRole('button',{name:'Eat out',exact:true}).click();assert.match(await f.locator('.p-week-agenda').innerText(),/Eating out/);await f.getByRole('button',{name:'Undo',exact:true}).click();console.log('PASS open-night Eat out and Undo');
 assert.deepEqual(errors,[]);console.log('PASS no browser runtime errors');
 } finally {await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});