// Writes sample files to test/out for manual testing of uploads.
import fs from "node:fs";
import { makeFit } from "./make-fit.js";
fs.mkdirSync("test/out", { recursive: true });
fs.writeFileSync("test/out/run.fit", makeFit());
fs.writeFileSync("test/out/mfp.csv", `Date,Meal,Calories,Fat (g),Saturated Fat,Polyunsaturated Fat,Monounsaturated Fat,Trans Fat,Cholesterol,Sodium (mg),Potassium,Carbohydrates (g),Fiber,Sugar,Protein (g),Vitamin A,Vitamin C,Calcium,Iron,Note
2026-10-26,Lunch,700,20,5,2,8,0,100,800,600,70,8,10,50,10,20,15,10,
2026-10-26,Dinner,800,25,8,3,10,0,120,900,700,80,10,12,50,10,20,15,10,
2026-10-26,Snacks,400,10,4,1,3,0,0,200,100,60,1,40,8,0,0,2,1,beer
2026-10-27,Lunch,650,18,5,2,8,0,90,700,500,60,7,8,55,10,20,15,10,
2026-10-27,Dinner,900,30,9,3,12,0,130,950,800,90,9,10,60,10,20,15,10,
`);
fs.writeFileSync("test/out/weights.csv", "Date,Weight\n2026-10-24,93.4\n2026-10-25,93.1\n");
console.log("fixtures written to test/out/");
