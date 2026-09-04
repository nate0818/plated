// Sample preview regression checks. Requires Playwright and Chrome.
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
 const page=await browser.newPage({viewport:{width:413,height:959},hasTouch:true});page.setDefaultTimeout(8000);
 const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto(process.env.PLATED_PREVIEW_URL||'http://127.0.0.1:8769/');
 const f=page.frameLocator('iframe'),rows=f.locator('.p-mealrow[data-open-date]');
 async function pause(){await page.waitForTimeout(420)}
 async function mouseHold(row){const b=await row.boundingBox();await page.mouse.move(b.x+180,b.y+b.height/2);await page.mouse.down();await pause();return b}
 await mouseHold(rows.filter({hasText:'Salmon'}));await page.mouse.up();
 await f.getByRole('button',{name:"Who's cooking",exact:true}).click();await f.getByRole('button',{name:'Sam',exact:true}).click();
 assert.match(await rows.filter({hasText:'Salmon'}).innerText(),/Sam cooks/);await f.getByRole('button',{name:'Undo',exact:true}).click();console.log('PASS hold options assign cook and undo');
 const source=await mouseHold(rows.filter({hasText:'Salmon'})),dest=await rows.filter({hasText:'Tomato'}).boundingBox();
 await page.mouse.move(dest.x+180,dest.y+dest.height/2,{steps:15});assert.match(await f.locator('.p-drag-status').innerText(),/Swap with Tomato/);await page.mouse.up();await pause();
 assert.match(await f.locator('[data-open-date="2026-09-04"]').innerText(),/Tomato/);await f.getByRole('button',{name:'Undo',exact:true}).click();console.log('PASS hold and drag swaps dinners');
 const session=await page.context().newCDPSession(page);
 async function touch(type,x,y){await session.send('Input.dispatchTouchEvent',{type,touchPoints:['touchEnd','touchCancel'].includes(type)?[]:[{x,y,id:1,radiusX:3,radiusY:3}]})}
 let b=await rows.filter({hasText:'Salmon'}).boundingBox(),d=await rows.filter({hasText:'Tomato'}).boundingBox();
 await touch('touchStart',b.x+180,b.y+b.height/2);await pause();for(let n=1;n<=10;n++){await touch('touchMove',b.x+180,b.y+b.height/2+(d.y-b.y)*n/10);await page.waitForTimeout(15)}
 assert.match(await f.locator('.p-drag-status').innerText(),/Swap with Tomato/);await touch('touchCancel');assert.match(await f.locator('[data-open-date="2026-09-04"]').innerText(),/Salmon/);assert.equal(await f.locator('.p-drag-ghost').count(),0);console.log('PASS touch hold and cancellation preserves dinner dates');
 await pause();b=await rows.filter({hasText:'Salmon'}).boundingBox();d=await rows.filter({hasText:'Tomato'}).boundingBox();
 await touch('touchStart',b.x+180,b.y+b.height/2);await pause();for(let n=1;n<=10;n++){await touch('touchMove',b.x+180,b.y+b.height/2+(d.y-b.y)*n/10);await page.waitForTimeout(15)}await touch('touchEnd');await pause();
 assert.match(await f.locator('[data-open-date="2026-09-04"]').innerText(),/Tomato/);await f.getByRole('button',{name:'Undo',exact:true}).click();console.log('PASS touch hold moves a dinner');
 await f.locator('[data-action="calendar-mode:month"]').click();b=await mouseHold(rows.filter({hasText:'Salmon'}));d=await f.locator('[data-calendar-day="2026-09-06"]').boundingBox();await page.mouse.move(d.x+d.width/2,d.y+d.height/2,{steps:20});await page.mouse.up();await pause();assert.equal(await f.locator('[data-calendar-day="2026-09-06"]').getAttribute('aria-pressed'),'true');assert.match(await rows.innerText(),/Salmon/);await f.getByRole('button',{name:'Undo',exact:true}).click();console.log('PASS month calendar accepts dinner drops');
 await f.getByRole('button',{name:'Recipes',exact:true}).click();await f.getByRole('button',{name:'Salmon with lemon butter Salmon with lemon butter 25 min · Makes 4',exact:true}).click();await f.getByRole('button',{name:'Edit',exact:true}).click();
 await f.getByRole('button',{name:'Reorder step 1',exact:true}).scrollIntoViewIfNeeded();
 const originals=await f.locator('[data-step]').evaluateAll(xs=>xs.map(x=>x.value));
 const grip=f.getByRole('button',{name:'Reorder step 1',exact:true});b=await grip.boundingBox();d=await f.locator('[data-step-row]').nth(1).boundingBox();
 await page.mouse.move(b.x+b.width/2,b.y+b.height/2);await page.mouse.down();await pause();await page.mouse.move(d.x+180,d.y+d.height-8,{steps:18});await page.mouse.up();await pause();
 let reordered=await f.locator('[data-step]').evaluateAll(xs=>xs.map(x=>x.value));assert.deepEqual(reordered,[originals[1],originals[0],originals[2]]);console.log('PASS step grip reorders draft without losing text');
 await f.getByRole('button',{name:'Reorder step 1',exact:true}).click();await f.getByRole('button',{name:'Move down',exact:true}).click();assert.deepEqual(await f.locator('[data-step]').evaluateAll(xs=>xs.map(x=>x.value)),originals);console.log('PASS step menu provides an alternative to dragging');
 b=await f.getByRole('button',{name:'Reorder step 1',exact:true}).boundingBox();d=await f.locator('[data-step-row]').nth(1).boundingBox();
 await touch('touchStart',b.x+b.width/2,b.y+b.height/2);await pause();await touch('touchMove',d.x+180,d.y+d.height-8);await touch('touchCancel');
 assert.deepEqual(await f.locator('[data-step]').evaluateAll(xs=>xs.map(x=>x.value)),originals);assert.equal(await f.locator('.p-drag-ghost').count(),0);console.log('PASS cancelled step drag preserves the draft');
 await pause();b=await f.getByRole('button',{name:'Reorder step 1',exact:true}).boundingBox();d=await f.locator('[data-step-row]').nth(1).boundingBox();
 await touch('touchStart',b.x+b.width/2,b.y+b.height/2);await pause();await touch('touchMove',d.x+180,d.y+d.height-8);await touch('touchEnd');await pause();
 assert.deepEqual(await f.locator('[data-step]').evaluateAll(xs=>xs.map(x=>x.value)),[originals[1],originals[0],originals[2]]);console.log('PASS touch grip reorders steps');
 await f.getByRole('button',{name:'Save',exact:true}).click();assert.match(await f.locator('.p-content').innerText(),/1\s+Cook the salmon/);console.log('PASS saved recipe retains reordered steps');
 assert.deepEqual(errors,[]);console.log('PASS no browser runtime errors');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
