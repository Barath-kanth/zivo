export type Task = {
  id: string;
  title: string;
  description: string;
  category: string;
  laborFeeLkr: number;
  goodsBudgetLkr: number;
  lat: number;
  lng: number;
  requiredSkill: string;
  clientId: string;
  status: string;
  escrow: {
    laborHoldLkr: number;
    goodsHoldLkr: number;
    status: string;
  };
  confirmCode: string;
  createdAt: string;
};
